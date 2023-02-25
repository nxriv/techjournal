echo $1
echo $2
sudo adduser "$1"
sudo usermod -aG wheel $1
sudo echo "$2" | sudo passwd "$1" --stdin
su - $1 -c "ssh-keygen -t rsa -C 'test'"
ssh -t nicholas@10.0.5.151 "sudo adduser '$1' && sudo usermod -aG sudo $1"
su - $1 -c "ssh-copy-id $1@10.0.5.151"
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
cd /home/nicholas/.ssh/
