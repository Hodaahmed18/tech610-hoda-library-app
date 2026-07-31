# Library App, 2-tier deployment on AWS

## What I was trying to do

Deploy a Java Spring Boot library application connected to a MySQL database, across two separate EC2 instances on AWS. The goal was to get it working manually first, then work up through bash scripts and user data to make the whole thing increasingly automated.

## What I set up

Two Ubuntu 24.04 instances, both t3.micro in eu-west-1. One for the database, one for the app. Both sit in the same security group with the necessary ports open, 22 for SSH, 3306 for MySQL, and 5000 for the app itself.

---

## Stage 1, getting it working manually

### The database VM

First thing was getting MySQL installed and configured on the DB VM. After installing MySQL, I imported the library schema directly into it, then created a dedicated database user so the app could connect remotely rather than having to use root.

The key config change here was the bindIp setting. By default, MySQL only listens on localhost (127.0.0.1), which means nothing outside the same machine can reach it. I updated that to 0.0.0.0 so MySQL would accept connections from the app VM across the private network, then restarted MySQL to apply it.

```bash
sudo apt update -y && sudo apt upgrade -y
sudo apt install mysql-server -y
git clone https://github.com/Wahab-Sparta/LibraryFiles
sudo mysql < LibraryFiles/library-java17-mysql-app/library.sql
sudo mysql -e "
CREATE USER 'myuser'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON library.* TO 'myuser'@'%';
"
sudo sed -i 's|127.0.0.1|0.0.0.0|' /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql
```

Confirmed it was working by checking MySQL was active and bindIp was set correctly.

### The app VM

On the app side, the app is a Spring Boot Java project so it needs Java 17 and Maven to build and run. After installing those, I cloned the app code, set the three environment variables the app reads at startup (the database URL, username, and password), and started it with Maven.

The app reads its database connection details from a config file that references environment variables directly, so getting those set correctly in the same shell session that runs Maven was important.

```bash
sudo apt update -y && sudo apt upgrade -y
sudo apt install openjdk-17-jdk -y
sudo apt install maven -y
git clone https://github.com/Wahab-Sparta/LibraryFiles
export DB_HOST=jdbc:mysql://<DB_PRIVATE_IP>:3306/library
export DB_USER=myuser
export DB_PASS=password
cd LibraryFiles/library-java17-mysql-app/LibraryProject2/
mvn spring-boot:run
```

Once it was running I hit the authors endpoint to confirm the app was genuinely pulling data from the database:

```bash
curl http://<APP_PUBLIC_IP>:5000/authors
```

Got back a real JSON list of authors, end to end confirmed working.

---

## Stage 2, bash scripts

With the manual steps confirmed, I wrote two provisioning scripts that do the same thing automatically. The idea is you run the script on each VM rather than typing out each command manually.

The DB script handles everything on the database side. The app script handles the app side, with one thing to note: the DB private IP needs to be substituted in before running it, since that changes each time new instances are launched.

Both scripts are in the `scripts/` folder:
- [db_prov.sh](scripts/db_prov.sh)
- [app_prov.sh](scripts/app_prov.sh)

---

## Stage 3, user data

The final step was passing those same scripts as user data at instance launch time, so the whole setup runs automatically on first boot with no manual SSH at all.

I launched the DB instance first with `db_prov.sh` as its user data, waited for it to be running, grabbed its private IP, updated the app script with that IP, then launched the app instance with `app_prov.sh` as its user data.

```bash
aws ec2 run-instances \
  --image-id ami-08c7a4b4f234dfa77 \
  --instance-type t3.micro \
  --key-name hodas-tech610 \
  --security-group-ids sg-0538347c654274382 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=hoda-library-db-userdata}]' \
  --user-data file://scripts/db_prov.sh \
  --query 'Instances[0].InstanceId' \
  --output text
```

```bash
sed -i 's|DB_PRIVATE_IP|<DB_PRIVATE_IP>|' scripts/app_prov.sh

aws ec2 run-instances \
  --image-id ami-08c7a4b4f234dfa77 \
  --instance-type t3.micro \
  --key-name hodas-tech610 \
  --security-group-ids sg-0538347c654274382 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=hoda-library-app-userdata}]' \
  --user-data file://scripts/app_prov.sh \
  --query 'Instances[0].InstanceId' \
  --output text
```

Java and Maven take a few minutes to install so I gave it around 10 minutes before testing. Hit the same authors endpoint and got back the same JSON, fully automated, no manual steps on either instance.

---

