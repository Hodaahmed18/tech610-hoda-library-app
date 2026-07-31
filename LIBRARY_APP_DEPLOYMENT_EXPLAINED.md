# Library App, 2-tier deployment on AWS

## Aim

Deploy the Library Java Spring Boot application with a MySQL database on two separate EC2 instances on AWS, then automate the setup using bash scripts.

## Architecture

- **DB VM**: Ubuntu 24.04, t3.micro, eu-west-1, default VPC, MySQL 8.0
- **App VM**: Ubuntu 24.04, t3.micro, eu-west-1, default VPC, Java 17, Maven, Spring Boot on port 5000
- Both instances use the same security group, with ports 22, 80, 3000, 3306, and 5000 open inbound

## Level of automation achieved

Manual deployment confirmed working, then bash scripts written to automate both the database and application provisioning. User data and AMI levels were not reached within the available time.

## Part 1, manual deployment

### DB VM setup

SSH into the DB VM, then run the following in order:

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

**What each step does:**
- Installs MySQL server
- Clones the LibraryFiles repo which contains the library.sql schema file
- Imports the library database schema into MySQL
- Creates a dedicated user with access from any IP (`%`), rather than using the root user
- Changes the bindIp from `127.0.0.1` (localhost only) to `0.0.0.0` (all interfaces), so the app VM can connect remotely
- Restarts MySQL to apply the config change

**Confirmed working:**
```bash
sudo systemctl status mysql | grep Active
grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf
```
Output: `Active: active (running)` and `bind-address = 0.0.0.0`

### App VM setup

SSH into the app VM, note the DB VM's private IP first.

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

**Confirmed working:**
```bash
curl http://<APP_PUBLIC_IP>:5000/authors
```
Returns a JSON list of authors from the database, confirming full end-to-end connectivity.

## Part 2, bash scripts

Scripts are saved in the `scripts/` folder of this repo.

**db_prov.sh**: automates the entire DB VM setup, install MySQL, import the schema, create the user, fix bindIp, restart MySQL.

**app_prov.sh**: automates the app VM setup, install Java 17 and Maven, clone the app files, export env vars, and run the app. Replace `DB_PRIVATE_IP` in the script with the actual DB VM private IP before running.

Links:
- [db_prov.sh](scripts/db_prov.sh)
- [app_prov.sh](scripts/app_prov.sh)

## Blockers and how they were resolved

**1. Instances terminated by a classmate by accident mid-deployment.**
Both EC2 instances were terminated while the deployment was in progress. Both were relaunched fresh from scratch using the AWS CLI, and the full setup was repeated.

**2. Port 3306 not open in the security group.**
The app VM could not connect to the database at all, connection attempts timed out. Adding an inbound rule for port 3306 to the shared security group resolved this immediately.

**3. Environment variables not persisting through Maven.**
Exporting `DB_HOST`, `DB_USER`, and `DB_PASS` in a script and then running `mvn spring-boot:run` manually afterward in a new shell meant the exports were gone. Fixed by passing the variables inline on the same command:
```bash
DB_HOST=jdbc:mysql://172.31.54.82:3306/library DB_USER=myuser DB_PASS=password mvn spring-boot:run
```
Or ensuring the script itself calls `mvn spring-boot:run` in the same shell session immediately after exporting.

**4. Spring Boot failing with "Unable to determine Dialect".**
This was caused by the env vars not being set correctly, Spring Boot could not determine the database type because it had no valid connection URL. Once env vars were correctly passed, this error disappeared.

## Part 3, user data deployment

Rather than SSHing into each instance and running scripts manually, the same provisioning scripts were passed directly as user data at instance launch time, so everything installs and configures automatically on first boot with no manual intervention required.

**Launching the DB instance with user data:**
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

**Get the DB VM's private IP once running:**
```bash
aws ec2 describe-instances --instance-ids <DB_INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text
```

**Update the app script with the real DB private IP:**
```bash
sed -i 's|DB_PRIVATE_IP|<DB_PRIVATE_IP>|' scripts/app_prov.sh
```

**Launching the app instance with user data:**
```bash
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

User data runs automatically in the background on first boot. Java and Maven installs take several minutes, so allow 5-10 minutes before testing.

**Confirmed working:**
```bash
curl http://<APP_PUBLIC_IP>:5000/authors
```
Returned the full authors JSON with no manual SSH or configuration required on either instance.

## Second deliverable

Full documentation and scripts:
```
https://github.com/Hodaahmed18/tech610-hoda-library-app
```
