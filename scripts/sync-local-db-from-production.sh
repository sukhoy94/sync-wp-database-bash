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

# Set URL variable from environment variable
LOCAL_URL="$LOCAL_HOST:$LOCAL_PORT"

# Set backup directory based on current year and month
BACKUP_DIR="$SCRIPT_DIR/backups/$(date +'%Y/%m')/local_sync_$(date +'%Y-%m-%d_%H-%M-%S')"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Generate backup file name with "local_" prefix
BACKUP_FILE="$BACKUP_DIR/local_backup_$(date +'%Y-%m-%d_%H-%M-%S').sql"

# Dump local MySQL database as backup
echo "Dumping local database as backup to $BACKUP_FILE ..."
docker exec $MARIADB_CONTAINER_NAME mysqldump -u $LOCAL_DB_USER -p$LOCAL_DB_PASSWORD $LOCAL_DB_NAME > "$BACKUP_FILE"

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
scp "$SSH_LOGIN@$SSH_SERVER:database_dump.sql" "$SCRIPT_DIR/database_dump.sql"

# Check if the file transfer was successful
if [ $? -eq 0 ]; then
    echo "Database dump transferred successfully."
else
    echo "Error transferring database dump."
    exit 1
fi

# Import the database dump file locally
echo "Importing database dump locally..."
docker cp "$SCRIPT_DIR/database_dump.sql" $MARIADB_CONTAINER_NAME:/var/lib/mysql

# Check if the import was successful
if [ $? -eq 0 ]; then
    echo "Database dump imported successfully."
else
    echo "Error importing database dump."
    exit 1
fi

# Execute SQL file in the MySQL container
echo "Executing SQL file in MySQL container..."
docker exec $MARIADB_CONTAINER_NAME bash -c "mysql -u $LOCAL_DB_USER -p'$LOCAL_DB_PASSWORD' $LOCAL_DB_NAME < /var/lib/mysql/database_dump.sql"

# Check if the SQL file execution was successful
if [ $? -eq 0 ]; then
    echo "SQL file executed successfully."
else
    echo "Error executing SQL file."
    exit 1
fi

# Update URLs in wp_posts table locally
echo "Updating URLs in wp_posts table..."
docker exec $MARIADB_CONTAINER_NAME mysql -u $LOCAL_DB_USER -p$LOCAL_DB_PASSWORD $LOCAL_DB_NAME -e "UPDATE wp_posts SET post_content = REPLACE(post_content, '$REMOTE_URL', '$LOCAL_URL');"

# Update URLs in wp_options table locally
echo "Updating URLs in wp_options table..."
docker exec $MARIADB_CONTAINER_NAME mysql -u $LOCAL_DB_USER -p$LOCAL_DB_PASSWORD $LOCAL_DB_NAME -e "UPDATE wp_options SET option_value = REPLACE(option_value, '$REMOTE_URL', '$LOCAL_URL') WHERE option_name IN ('siteurl', 'home');"

echo "URLs updated in wp_posts and wp_options tables."

# Clean remote database dump files
echo "Cleaning up database dump files..."
ssh "$SSH_LOGIN@$SSH_SERVER" "rm database_dump.sql"

# move remote dump to backups
mv "$SCRIPT_DIR/database_dump.sql" "$BACKUP_DIR/remote_dump.sql"

# Write migration log entry
echo "" >> "$BACKUP_DIR/migration_log.txt"
echo "//-----------------------------------------------------//" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration from remote server complete!" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration description: $MIGRATION_DESCRIPTION" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration time: $(date +'%Y-%m-%d %H:%M:%S')" >> "$BACKUP_DIR/migration_log.txt"
echo "Migration log updated."
echo "Migration complete!"