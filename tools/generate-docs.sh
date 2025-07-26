#!/bin/bash
# Generate documentation from existing markdown files
set -e

echo "📚 Generating documentation..."

# Create docs directory if it doesn't exist
mkdir -p docs/generated

# Generate README index
echo "📄 Creating documentation index..."
cat > docs/generated/README.md << 'EOF'
# GeuseMaker Documentation

## Quick Start
- [Getting Started](../getting-started/)
- [Prerequisites](../getting-started/prerequisites.md)

## Deployment Guides
- [AWS Deployment](../reference/cli/deployment.md)
- [Management Commands](../reference/cli/management.md)

## API Reference
- [Service APIs](../reference/api/)
- [CLI Reference](../reference/cli/)

## Security
- [Security Guide](../security-guide.md)

## Troubleshooting
- [Common Issues](../setup/troubleshooting.md)
EOF

# Generate command reference from Makefile
echo "⚙️  Generating command reference..."
echo "# Make Commands Reference" > docs/generated/commands.md
echo "" >> docs/generated/commands.md
echo "Generated from Makefile on $(date)" >> docs/generated/commands.md
echo "" >> docs/generated/commands.md

# Extract commands and descriptions from Makefile
grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | \
    sort | \
    awk 'BEGIN {FS = ":.*?## "}; {printf "- **%s**: %s\n", $1, $2}' >> docs/generated/commands.md

echo "✅ Documentation generated in docs/generated/"
echo "📋 Files created:"
find docs/generated -name "*.md" -exec echo "  - {}" \;