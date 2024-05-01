# Synchronize wordpress databases with bash (docker based version)

Hi! This project contains 2 scripts which I'm using to synchronize my wordpress docker-based projects databases in 
two directions: 
- sync local db (pull changes from production database)
- sync production db (pull changes from local db to production)


### Project structure

- Makefile file with 2 commands to run:

```
make sync_local_db
make sync_remote_db
```

- scripts/ folder which contains:
```
.env
sync-local-db-from-production.sh
sync-production-db-from-local.sh
```
### ENVs description

- `SSH_LOGIN`: Your SSH login username for connecting to the remote server.
- `SSH_SERVER`: The hostname or IP address of the remote server you want to connect to via SSH.
- `LOCAL_DB_USER`: The username of the local MySQL/MariaDB database.
- `LOCAL_DB_PASSWORD`: The password of the local MySQL/MariaDB database.
- `LOCAL_DB_NAME`: The name of the local MySQL/MariaDB database.
- `MARIADB_CONTAINER_NAME`: The name of the Docker container running MySQL/MariaDB locally.
- `REMOTE_DB_HOST`: The hostname or IP address of the remote MySQL/MariaDB database server.
- `REMOTE_DB_USER`: The username of the remote MySQL/MariaDB database.
- `REMOTE_DB_PASSWORD`: The password of the remote MySQL/MariaDB database.
- `REMOTE_DB_NAME`: The name of the remote MySQL/MariaDB database.
- `REMOTE_ADMIN_USER`: The username used for administrative tasks on the remote server, if applicable.
- `LOCAL_HOST`: The hostname or IP address of your local machine.
- `LOCAL_PORT`: The port number where your local server is running (e.g., for a web server).
- `REMOTE_URL`: The URL of the remote server, which may be used for updating URLs in WordPress or similar applications.

# Flow

## 1. Sync local database

Run:
```
make sync_local_db
```

### Script Overview

#### Setting Up Environment
- Loads environment variables from a `.env` file containing database and server configurations.

#### Asking for Migration Description
- Prompts the user to enter a short description for the migration.

#### Backup Directory
- Creates a directory structure for storing backups based on the current date and time.

#### Dumping Local Database
- Creates a backup of the local MySQL database running in a Docker container.
- Saves the backup to a file with a timestamp in the backup directory.

#### Dumping Remote Database
- Dumps the remote MySQL database directly to a file on the remote server using SSH.
- Excludes the `wp_users` table and saves the dump to a file named `database_dump.sql` on the remote server.

#### Transferring Remote Dump
- Transfers the database dump file from the remote server to the local machine using SCP.
- Saves the file in the script's directory.

#### Importing Remote Dump Locally
- Imports the database dump file into the local MySQL database running in a Docker container.

#### Executing SQL File
- Executes the SQL file containing the database dump in the local MySQL container.

#### Updating URLs
- Updates URLs in the `wp_posts` and `wp_options` tables of the local database to replace remote URLs with local URLs.

#### Cleaning Up
- Removes the database dump file from the remote server.
- Moves the remote dump file to the backup directory.

#### Logging Migration
- Logs migration details, including the migration description, timestamp, and updates to a migration log file in the backup directory.

#### Completing Migration
- Prints a message indicating that the migration is complete.

## 2. Sync remote database
Run:
```
make sync_remote_db
```
### MySQL Database Migration Script Overview

#### Setting Up Environment
- Retrieves the directory of the script and loads environment variables from a `.env` file containing database and server configurations.

#### Asking for Migration Description
- Prompts the user to enter a short description for the migration.

#### Backup Directory
- Creates a directory structure for storing backups based on the current date and time.

#### Dumping Local Database
- Dumps the local MySQL database running in a Docker container.
- Excludes the `wp_users` table and saves the dump to a file named `local_database_dump.sql` in the backup directory.

#### Transferring Local Dump to Remote Server
- Transfers the database dump file to the remote server using SCP.

#### Dumping Remote Database
- Dumps the remote MySQL database directly to a file on the remote server using SSH.
- Excludes the `wp_users` table and saves the dump to a file named `database_dump.sql` on the remote server.

#### Importing Remote Dump
- Connects to the SSH server and imports the database dump into the remote MySQL database.
- Updates URLs in the `wp_posts` and `wp_options` tables of the remote database.
- Cleans up temporary files after the import process.

#### Logging Migration
- Logs migration details, including the migration description, timestamp, and updates, to a migration log file in the backup directory.

#### Completing Migration
- Prints a message indicating that the migration is complete.


