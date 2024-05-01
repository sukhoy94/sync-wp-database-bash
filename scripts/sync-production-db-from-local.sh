#!/bin/bash

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Load environment variables from .env file
source "$SCRIPT_DIR/.env"

# Function to ask user for migration description
ask_for_description() {
    echo "Please enter a short description for this migration:"
    read -r MIGRATION_DESCRIPTION
    if [ -z "$MIGRATION_DESCRIPTION" ]; then
        echo "Migration description cannot be empty. Please try again."
        ask_for_description
    fi
}

# Ask user for migration description
ask_for_description

# Set backup directory based on current year and month
BACKUP_DIR="$SCRIPT_DIR/backups/$(date +'%Y/%m')/prod_sync_$(date +'%Y-%m-%d_%H-%M-%S')"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Dump local MySQL database
echo "Dumping local database..."
dump_output=$(docker exec $MARIADB_CONTAINER_NAME mysqldump -u $LOCAL_DB_USER -p$LOCAL_DB_PASSWORD $LOCAL_DB_NAME --ignore-table=$LOCAL_DB_NAME.wp_users 2>&1)

# Check if dump command executed successfully
if [ $? -ne 0 ]; then
    echo "Error dumping local database:"
    echo "$dump_output"
    exit 1
fi

echo "$dump_output" > "$BACKUP_DIR/local_database_dump.sql"

# Transfer the database dump file to the remote server
echo "Transferring database dump to remote server..."
scp "$BACKUP_DIR/local_database_dump.sql" "$SSH_LOGIN@$SSH_SERVER:/tmp"


# Dump remote MySQL database directly to the specified file
echo "Dumping remote database to file..."
ssh_result=$(ssh "$SSH_LOGIN@$SSH_SERVER" "mysqldump -h $REMOTE_DB_HOST -u $REMOTE_DB_USER -p'$REMOTE_DB_PASSWORD' $REMOTE_DB_NAME --ignore-table=$REMOTE_DB_NAME.wp_users --no-tablespaces > database_dump.sql" 2>&1)

# Check if the SSH command was successful
if [ $? -eq 0 ]; then
    echo "Remote database dumped successfully."
else
    echo "Error dumping remote database: $ssh_result"
    exit 1
fi

# Check if the database_dump.sql file was created on the remote server
ssh "$SSH_LOGIN@$SSH_SERVER" "[ -e database_dump.sql ] && echo 'database_dump.sql exists' || echo 'database_dump.sql does not exist'"

# Transfer the database dump file from the remote server
echo "Transferring database dump from remote server..."
scp "$SSH_LOGIN@$SSH_SERVER:database_dump.sql" "$BACKUP_DIR/production_dump.sql"

# Connect to SSH server and import the database dump
echo "Connecting to SSH server and importing database dump..."
ssh -T "$SSH_LOGIN@$SSH_SERVER" <<EOF
    # Import the database dump
    echo "Importing database dump..."
    mysql -h "$REMOTE_DB_HOST" -u "$REMOTE_DB_USER" -p"$REMOTE_DB_PASSWORD" "$REMOTE_DB_NAME" < /tmp/local_database_dump.sql

    # Check if import command executed successfully
    if [ $? -ne 0 ]; then
        echo "Error importing database dump"
        exit 1
    fi

    # Update URLs in wp_posts table
    echo "Updating URLs in wp_posts table..."
    mysql -h "$REMOTE_DB_HOST" -u "$REMOTE_DB_USER" -p"$REMOTE_DB_PASSWORD" "$REMOTE_DB_NAME" -e "UPDATE wp_posts SET post_content = REPLACE(post_content, 'localhost:8080', 'dusha-fund.com');"

    # Update URLs in wp_options table
    echo "Updating URLs in wp_options table..."
    mysql -h "$REMOTE_DB_HOST" -u "$REMOTE_DB_USER" -p"$REMOTE_DB_PASSWORD" "$REMOTE_DB_NAME" -e "UPDATE wp_options SET option_value = REPLACE(option_value, 'localhost:8080', 'dusha-fund.com') WHERE option_name IN ('siteurl', 'home');"

    echo "URLs updated in wp_posts and wp_options tables."

    # Remove the temporary dump file
    echo "Cleaning up..."
    rm /tmp/local_database_dump.sql
    rm database_dump.sql
EOF
# Write migration log entry
echo "" >> "$BACKUP_DIR/migration_log.txt"
echo "//-----------------------------------------------------//" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration to remote server complete!" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration description: $MIGRATION_DESCRIPTION" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration time: $(date +'%Y-%m-%d %H:%M:%S')" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration log updated."
echo "Migration complete!"