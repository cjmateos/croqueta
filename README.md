# Croqueta

## Overview

This is a tool/script that will automatically rotate the master SSH key in all servers that match a particular tag. This process is automated in a "safe-way" where changes are reverted if the script wasn't able to complete successfully.

The following tool is based on a Ruby script. Also, a docker image has been created to run the program in an easier way.

## Requisites

- [ruby](https://www.ruby-lang.org/en/downloads/) >= 2.5.0
- ruby gems:
  - aws-sdk-ec2
  - aws-sdk-s3
  - sshkey
  - colorize

To install the required gems you need to run the following commands:
```
gem install aws-sdk-ec2
gem install aws-sdk-s3
gem install sshkey
gem install colorize
```

Since this script uses the AWS Ruby SDK, you need to configure your environment to access to an AWS account:
- You need to have an IAM user with ACCESS KEY and SECRET KEY
- Install and configure **aws cli** with your credentials: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html
- The user must have privileges for accessing to EC2 instances and S3 buckets.

## Usage

Clone this repository.

```
git clone https://github.com/cjmateos/croqueta.git
```

Copy and rename the `conf/config.yaml.example` file as `conf/config.yaml` and set the parameters with your environment values. You must to configure the following keys:

- `region`: AWS region. E.g. 'us-east-1'
- `bucket`: S3 bucket in which the keys will be stored. E.g. 'mykeys-storage'
- `current_key_file`: Name of the current key file name (pem format) to access to the EC2 instances. E.g. 'current.pem'
- `keys_path`: Local path in your system where the keys are stored. E.g. 'keys'
- `ssh_user`: User to access to EC2 instances by using ssh protocol. E.g. 'ec2-user'
- `tag_key`: Key tag of the target instances in which rotate the ssh key. E.g. 'Target'
- `tag_value`: Key value of the target instances in which rotate the ssh key. E.g. 'keyRenew'
- `rotate_key_prefix`: Prefix name for the new keys. E.g. 'EC2-Key'

**IMPORTANT**:
- You must to have an S3 bucket already created (the same you set in `bucket` option) in which you must have already stored your current private key file (pem format) in the root path. E.g. `s3://my-bucket/current.pem`
- Set the option `current_key_file` with the name of the pem file stored in the S3 bucket.

### Run from the source code

Once you have the configuration file ready, you can run the [`croqueta.rb`](croqueta.rb) script as follows:

```
ruby croqueta.rb
```

### Run from docker-compose

From the repository root folder, run the following command:

```
docker-compose up
```

The docker image `cjmateos/croqueta:latest` is pulled from Docker Hub.

### Run from docker

From the repository root folder, run the following command:

```
docker run -v ~/.aws:/home/nonroot/.aws -v $(pwd)/conf:/opt/croqueta/conf -v $(pwd)/keys:/opt/croqueta/keys cjmateos/croqueta:latest
```

NOTE: The first host path volume maps the folder where you must have the configuration for accessing to your AWS account.

## Description

The following section describes the implementation details of the proposed solution.

The program is composed by a main script, [`croqueta.rb`](croqueta.rb) and a functions library [`/lib/functions.rb`](lib/functions.rb) where the operations with keys and AWS EC2 instances and S3 are implemented. Also you can find a file with auxiliar functions called [`/lib/aux.rb`](lib/aux.rb).

Basically, the script expects you have an S3 bucket already created where the current key file can be found in the root path of the bucket. The key file is downloaded to your system. Then, all the EC2 instances with the target tag are identified. The script creates a new key pair and imports it to EC2. It tries to connect with each of the target instances to add a new ssh key. If the connection is success, the old key is removed. Finally, the new key is stored in the S3 bucket as the new current key. Also a backup of the key is saved in the bucket. If for any reason, the new key could not be added to some of the target instances, the process is cancelled and the old key is recovered in each updated instance.

### Detailed process

The main script [`croqueta.rb`](croqueta.rb) checks the configuration file which is defined as a YAML file in `conf/config.yaml`. With the values of the configuration file, the main script calls some functions defined in [`functions.rb`](lib/functions.rb) to perform the key rotation process. Specifically, the following operations are performed:
- Gets the id of the EC2 instances which contains the tag and value specified in the configuration file.
- Download from S3 the key which is currently used by the tagged instances.
- Generates a new key pair and imports the public key to the AWS EC2 Key Pair repository. The new key name has the following format: `[rotate_key_prefix]-timestamp`. E.g. `EC2-Key-1551306873`.
- For each EC2 tagged instance:
  - Add the public key portion of the SSH key pair to the `~./ssh/authorized_keys` file.
  - Test ssh logging on the instance with the new key.
    - If the test passes, the old key is removed from the EC2 instance. Furthermore, the instance is added to an array of updated instances (for rollback purposes).
    - If the test fails, the rollback process is executed:
      - Checks the array of updated instances and recovers the previous key in all of them.
      - Test ssh logging on each instance with the recovered key.
      - Delete the new key from the EC2 Key Pair repository.
- If the key has been successfully rotated on every tagged EC2 instances, the new key is uploaded to the S3 bucket (specified in the configuration file). It is saved in the `s3://BUCKET/stored-keys` folder with it original name (backup) and also in the `s3://BUCKET/` root path with the name specified as the configuration key `current_key_file`. E.g. `s3://BUCKET/current.pem`

### Example of rollback process

In the following video, you can see an example of an execution in which the process fails and the rollback is performed.

TODO

## Testing environment

To test the solution, I have used a personal AWS account.

In the AWS account there are created five EC2 instances in the us-east-1 region (cjmateos1, cjmateos2, ...). Three of these instances are tagged with the target tag (`Target`, `keyRenew`).

In addition, there is an S3 bucket (private) called `croqueta-keys`. It contains the `current.pem` file in its root path. Also has a folder `stored-keys` with previous keys and the key for accessing to the non-tagged instances.

You can perform the tests in this environment by using an AWS user for this account, and the same configuration of the [`config.yaml.example`](conf/config.yaml.example) file.
