#!/bin/bash
echo "Updating..."
sudo apt update -y
echo "Upgrading..."
sudo apt upgrade -y

echo "Installing Java 17..."
sudo apt install openjdk-17-jdk -y

echo "Installing Maven..."
sudo apt install maven -y

echo "Cloning app files..."
git clone https://github.com/Wahab-Sparta/LibraryFiles

echo "Setting environment variables..."
export DB_HOST=jdbc:mysql://DB_PRIVATE_IP:3306/library
export DB_USER=myuser
export DB_PASS=password

echo "Running app..."
cd LibraryFiles/library-java17-mysql-app/LibraryProject2/
mvn spring-boot:run
