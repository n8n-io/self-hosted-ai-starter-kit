#!/bin/bash

# Initialize GitHub CLI if token is provided
if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token
    echo "GitHub CLI authenticated successfully"
fi

# Initialize dotenv-vault if available
if command -v dotenv-vault &> /dev/null; then
    echo "dotenv-vault is available"
fi

# Execute the original command
exec "$@"
