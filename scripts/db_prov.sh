#!/bin/bash
echo "Updating..."
sudo apt update -y
echo "Upgrading..."
sudo apt upgrade -y

echo "Installing MySQL..."
sudo apt install mysql-server -y

echo "Importing library database..."
git clone https://github.com/Wahab-Sparta/LibraryFiles
sudo mysql < LibraryFiles/library-java17-mysql-app/library.sql

echo "Creating database user..."
sudo mysql -e "
CREATE USER 'myuser'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON library.* TO 'myuser'@'%';
"

echo "Configuring bindIp..."
sudo sed -i 's|127.0.0.1|0.0.0.0|' /etc/mysql/mysql.conf.d/mysqld.cnf

echo "Restarting MySQL..."
sudo systemctl restart mysql
echo "Done."
