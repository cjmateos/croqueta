require 'yaml'
require_relative 'lib/functions.rb'

CONFIG_DIR = File.expand_path('../', __FILE__) + '/conf'
CONFIG_FILE = CONFIG_DIR + '/config.yaml'

begin
  configuration = YAML.load_file(CONFIG_FILE)
rescue StandardError => e
  print_error "The configuration cannot be read: #{e}"
  exit 1
end

# New private key
new_key_name = "#{configuration['rotate_key_prefix']}-#{Time.now.to_i}"
new_private_key_file = "#{new_key_name}.pem"
new_public_key_file = "#{new_key_name}.pub"

# MAIN
separator
print_msg "Croqueta"
separator
print_msg "Simple ruby script to automate EC2 SSH keys rotation for AWS"
print_msg "- https://github.com/cjmateos/croqueta"
separator

begin
  instances = instances_ids(configuration)
  unless instances.length.zero?
    get_current_key(configuration)
    generate_key(configuration, new_key_name, new_private_key_file, new_public_key_file)
    ret = update_key(configuration, instances, new_key_name, new_private_key_file, new_public_key_file)
    if ret
      push_new_key(configuration, new_private_key_file)
    end
  else
    print_warn "Instances with tag/value '#{configuration['tag_key']}/#{configuration['tag_value']}' could not be found"
  end
rescue StandardError => e
  print_error "Something went wrong!"
  print_msg "#{e}"
  print_inline "Removing key #{new_key_name}..."
  delete_key(configuration, new_key_name)
  ok
  exit 1
end
