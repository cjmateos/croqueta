require 'aws-sdk-ec2'
require 'aws-sdk-s3'
require 'sshkey'
require_relative 'utils.rb'

def instances_ids(configuration)
  intances_id = []
  ec2 = Aws::EC2::Resource.new(region: configuration['region'])
  ec2.instances({filters: [{name: "tag:#{configuration['tag_key']}", values: [configuration['tag_value']]}]}).each do |i|
    intances_id << i.id
  end
  intances_id
end

def generate_key(configuration, key_name, private_key_file, public_key_file)
  ec2 = Aws::EC2::Client.new(region: configuration['region'])
  # Create a key pair.
  begin
    key_pair = ec2.create_key_pair({
      key_name: key_name
    })
    print_info "Created new key pair: '#{key_pair.key_name}'"

    # Create private key pem file
    File.open("#{configuration['keys_path']}/#{private_key_file}", 'w') { |f| f.write(key_pair.key_material) }
    File.chmod(0600, "#{configuration['keys_path']}/#{private_key_file}")
    print_info "New private key file: #{configuration['keys_path']}/#{private_key_file}"

    # Create public key ssh file
    file = File.read(File.expand_path("#{configuration['keys_path']}/#{private_key_file}"))
    k = SSHKey.new(file, comment: key_name)
    File.open("#{configuration['keys_path']}/#{public_key_file}", 'w') { |f| f.write(k.ssh_public_key) }
    File.chmod(0600, "#{configuration['keys_path']}/#{public_key_file}")
    print_info "New public key file: #{configuration['keys_path']}/#{public_key_file}"
  rescue Aws::EC2::Errors::InvalidKeyPairDuplicate
    puts "A key pair named '#{key_pair_name}' already exists."
  end
end

def delete_key(configuration, key_name)
  ec2 = Aws::EC2::Client.new(region: configuration['region'])
  ec2.delete_key_pair({key_name: key_name})
end

def update_key(configuration, instances, new_key_name, new_private_key_file, new_public_key_file)
  ret_value = false
  updated = []
  ec2 = Aws::EC2::Resource.new(region: configuration['region'])
  instance_ssh_user = configuration['ssh_user']
  instances.each do |i|
    ret_value = false
    instance = ec2.instance(i)
    instance_public_dns = configuration['access'] == 'public' ? instance.public_dns_name : instance.private_ip_address
    if instance.state.name == 'running'
      separator
      print_inline "Adding new key to EC2 instance #{instance.id}: "
      # Old public key file
      old_public_key = `ssh -o StrictHostKeyChecking=no -q -i #{configuration['keys_path']}/#{configuration['current_key_file']} #{instance_ssh_user}@#{instance_public_dns} 'cat ~/.ssh/authorized_keys'`.chomp
      old_public_key_name = old_public_key.split(" ").last
      ret = system("echo $(cat #{configuration['keys_path']}/#{new_public_key_file}) | ssh -o StrictHostKeyChecking=no -q -i #{configuration['keys_path']}/#{configuration['current_key_file']} #{instance_ssh_user}@#{instance_public_dns} 'cat >> ~/.ssh/authorized_keys'")
      if ret
        ok
        if test_key(configuration, new_private_key_file, instance_public_dns)
          ret_value = remove_key(configuration, old_public_key_name, new_private_key_file, instance_public_dns)
          updated << {:id => instance.id, :key => old_public_key} if ret_value
        else
          print_inline "Removing new key from EC2 instance..."
          ret = system("ssh -o StrictHostKeyChecking=no -q -i #{configuration['keys_path']}/#{configuration['current_key_file']} #{instance_ssh_user}@#{instance_public_dns} sed -i '2d' .ssh/authorized_keys")
          ret ? ok : error
        end
      else
        error
      end
    end
    if ret_value == false
      print_error "Impossible to rotate key in instance #{instance.id}"
      rollback(updated, configuration, new_key_name, new_private_key_file)
      separator
      print_inline "Removing key #{new_key_name}..."
      delete_key(configuration, new_key_name)
      ok
      break
    end
  end
  ret_value
end

def test_key(configuration, new_private_key_file, instance_public_dns)
  ret_value = false
  print_inline "Testing new key..."
  test_value = 'Testing 123'
  `echo "#{test_value}" | ssh -o StrictHostKeyChecking=no -q -i "#{configuration['keys_path']}/#{configuration['current_key_file']}" "#{configuration['ssh_user']}@#{instance_public_dns}" 'cat > ~/.rotation_test_file'`
  new_test_value = `ssh -o StrictHostKeyChecking=no -q -i "#{configuration['keys_path']}/#{new_private_key_file}" "#{configuration['ssh_user']}@#{instance_public_dns}" 'cat ~/.rotation_test_file'`.chomp
  if test_value == new_test_value
    ok
    ret_value = true
  else
    error
  end
  ret_value
end

def remove_key(configuration, key_name, private_key_file, instance_public_dns)
  ret_value = false
  print_inline "Removing old key from EC2 instance..."
  ret = system("ssh -o StrictHostKeyChecking=no -q -i #{configuration['keys_path']}/#{private_key_file} #{configuration['ssh_user']}@#{instance_public_dns} sed -i '/.*#{key_name}/d' .ssh/authorized_keys")
  if ret
    ok
    ret_value = true
  else
    error
  end
  ret_value
end

def rollback(updated, configuration, key_name_delete, new_private_key_file)
  separator
  print_info "ROLLBACK PROCESS"
  updated.each do |i|
    separator
    instance = Aws::EC2::Instance.new(i[:id], configuration['region'])
    instance_public_dns = configuration['access'] == 'public' ? instance.public_dns_name : instance.private_ip_address
    print_inline "Recovering previous key to EC2 instance #{i[:id]}: "
    ret = system("echo '#{i[:key]}' | ssh -o StrictHostKeyChecking=no -q -i #{configuration['keys_path']}/#{new_private_key_file} #{configuration['ssh_user']}@#{instance_public_dns} 'cat >> ~/.ssh/authorized_keys'")
    if ret
      ok
      if test_key(configuration, new_private_key_file, instance_public_dns)
        remove_key(configuration, key_name_delete, configuration['current_key_file'], instance_public_dns)
      end
    else
      error
    end
  end
end

def get_current_key(configuration)
  s3 = Aws::S3::Resource.new(region: configuration['region'])
  obj = s3.bucket(configuration['bucket']).object(configuration['current_key_file'])
  obj.get(response_target: "#{configuration['keys_path']}/#{configuration['current_key_file']}")
  File.chmod(0600, "#{configuration['keys_path']}/#{configuration['current_key_file']}")
  print_info "Current key file downloaded at #{configuration['keys_path']}/#{configuration['current_key_file']}"
end

def push_new_key(configuration, new_key_file)
  separator
  s3 = Aws::S3::Resource.new(region: configuration['region'])
  obj = s3.bucket(configuration['bucket']).object("stored-keys/#{new_key_file}")
  obj.upload_file("#{configuration['keys_path']}/#{new_key_file}")
  print_info "New key file uploaded to S3 at s3://#{configuration['bucket']}/stored-keys/#{new_key_file}"
  obj = s3.bucket(configuration['bucket']).object(configuration['current_key_file'])
  obj.upload_file("#{configuration['keys_path']}/#{new_key_file}")
  FileUtils.cp("#{configuration['keys_path']}/#{new_key_file}","#{configuration['keys_path']}/#{configuration['current_key_file']}")
  print_info "New key file uploaded to S3 at s3://#{configuration['bucket']}/#{configuration['current_key_file']}"
end
