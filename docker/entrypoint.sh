#!/bin/bash
set -e

# Wait for database to be ready
echo "Waiting for database..."
while ! python -c "
import sys
import psycopg2
try:
    conn = psycopg2.connect(
        dbname='${DB_NAME}',
        user='${DB_USER}',
        password='${DB_PASSWORD}',
        host='${DB_HOST}',
        port='${DB_PORT:-5432}'
    )
    conn.close()
    sys.exit(0)
except psycopg2.OperationalError:
    sys.exit(1)
" 2>/dev/null; do
    echo "Database is unavailable - sleeping"
    sleep 1
done
echo "Database is up!"

# Run migrations if DJANGO_RUN_MIGRATIONS is set
if [ "$DJANGO_RUN_MIGRATIONS" = "true" ]; then
    echo "Running migrations..."
    python manage.py migrate --noinput
fi

# Execute the main command
exec "$@"