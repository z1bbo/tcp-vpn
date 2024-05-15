An experimental TCP-only ipv4-only VPN server I hacked together before visiting China.

Even the TLS handshake is encrypted! Then it goes symetrically encrypted.

It's designed to be easy to set up in <5 minutes, and run for (almost) free on AWS Free Tier.

I used it together with a script that sends random requests to http-only websites, for further obfuscation of the TLS traffic patterns.

It got me around a total of 2 hours of usage before I got blocked by the Great Firewall.

I'm far from an expert, there are probably bugs & lots was written by ChatGPT4, so be careful!

On Linux you'll have to adjust the openvpn up down scripts a bit.


# How to use:

## 0. Create the state bucket and import it into Terraform
First make up a unique `$state_bucket` name to hold the tf state, decide the `$aws_region`, create the bucket:
```bash
cd tf
aws s3api create-bucket --bucket $state_bucket --create-bucket-configuration LocationConstraint=$aws_region
```
Then edit `locals.tf` and `tf.tf`, set the bucket name and desired region (defaults to `ap-southeast-1`).

Then initialize terraform and import the bucket we just created (it won't be auto-deleted on destroy since it's versioned).
```bash
terraform init
terraform import aws_s3_bucket.tfstate $name
```

## 1. Deploy with TF

In the `tf` directory, run `terraform apply`, confirm with `yes`.

This will create the necessary AWS resources, including the EC2 instance for the VPN server, the security group, and the secret in AWS Secrets Manager.
Take note of the outputted ip address, this is where we'll connect to later.

To destroy again later, delete the `infra.tf` and `iam.tf` files and apply again.

## 2. Retrieve the VPN Secret

Wait for 1-2 minutes for the startup scripts to finish, then retrieve the TLS secrets (should create a bunch of files).

```bash
aws secretsmanager get-secret-value --secret-id vpn_certs --query SecretBinary --output text | base64 --decode | tar -xz
```

## 3. Configure the VPN Client

Edit the OpenVPN configuration file at `client.ovpn`, replace the ip at line 6 with the public IP address outputted after `terraform apply`.

To be extra sure to prevent DNS leaks, you can also disable ipv6 on your machine, macOS:
`networksetup -setv6off Wi-Fi`, to enable again `networksetup -setv6automatic Wi-Fi`

## 5. Connect to the VPN Server

```bash
sudo openvpn --config client.ovpn
```
