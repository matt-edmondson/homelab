sudo timedatectl set-timezone Australia/Melbourne
sudo timedatectl set-ntp no
sudo apt update
sudo apt install -y auto-apt-proxy
sudo auto-apt-proxy
sudo apt update
sudo apt upgrade -y
sudo apt install -y build-essential git git-lfs curl wget net-tools ntp nvim fish apt-transport-https software-properties-common zip unzip ca-certificates gnupg
sudo git lfs install