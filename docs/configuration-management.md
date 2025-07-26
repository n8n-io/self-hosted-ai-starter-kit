# Centralized Configuration Management

## Overview

The GeuseMaker project now features a comprehensive centralized configuration management system that standardizes environment variables across all deployment types and environments. This system eliminates configuration scattering and provides a unified approach to managing application settings.

## Architecture

### Directory Structure

```
config/
├── defaults.yml                 # Base configuration values
├── environments/
│   ├── development.yml         # Development environment overrides
│   └── production.yml          # Production environment overrides
├── deployment-types.yml        # Deployment-specific configurations
└── templates/
    ├── docker-compose.yml.j2   # Docker Compose template
    └── environment.yml.j2      # Environment file template
```

### Core Components

1. **Configuration Library** (`lib/config-management.sh`)
   - Centralized configuration loading and validation
   - Environment file generation
   - Template processing
   - Cross-platform compatibility

2. **Configuration Files** (YAML format)
   - Hierarchical configuration with inheritance
   - Environment-specific overrides
   - Deployment type specialization

3. **Integration Layer**
   - Seamless integration with existing scripts
   - Backward compatibility maintained
   - Automatic fallback to legacy mode

## Configuration Hierarchy

The configuration system follows a hierarchical structure:

```
defaults.yml (base values)
    ↓
deployment-types.yml (deployment-specific)
    ↓
environments/[env].yml (environment-specific)
    ↓
runtime overrides (command line, environment variables)
```

### Configuration Inheritance

1. **Base Configuration** (`defaults.yml`)
   - Common settings across all environments
   - Default values for all services
   - Standard resource allocations

2. **Deployment Types** (`deployment-types.yml`)
   - Spot instance configurations
   - On-demand instance settings
   - Simple deployment options

3. **Environment Overrides** (`environments/[env].yml`)
   - Development-specific settings
   - Production configurations
   - Environment-specific resource limits

## Usage

### Basic Configuration Management

```bash
# Load configuration for development environment
source lib/config-management.sh
load_configuration "development"

# Get a specific configuration value
INSTANCE_TYPE=$(get_config_value "aws.instance_type")
REGION=$(get_config_value "aws.region")

# Generate environment file
generate_environment_file "development" ".env"
```

### Script Integration

All deployment scripts now automatically use the centralized configuration:

```bash
# The script will automatically load the appropriate configuration
./scripts/aws-deployment-unified.sh --environment development --deployment-type spot
```

### Makefile Commands

```bash
# Generate configuration for all environments
make config:generate

# Validate configuration files
make config:validate

# Show current configuration
make config:show

# Compare configurations between environments
make config:diff
```

## Configuration File Format

### Defaults Configuration (`config/defaults.yml`)

```yaml
# AWS Configuration
aws:
  region: us-east-1
  instance_type: g4dn.xlarge
  key_name: GeuseMaker-key
  stack_name: GeuseMaker

# Application Configuration
app:
  name: GeuseMaker
  version: latest
  port: 8080
  environment: development

# Docker Configuration
docker:
  registry: docker.io
  image_prefix: geusemaker
  compose_version: "3.8"

# Services Configuration
services:
  ollama:
    enabled: true
    port: 11434
    models:
      - llama2:7b
      - codellama:7b
  
  n8n:
    enabled: true
    port: 5678
    webhook_url: ""
  
  qdrant:
    enabled: true
    port: 6333
    memory_limit: 1gb
```

### Environment Overrides (`config/environments/development.yml`)

```yaml
# Development-specific overrides
aws:
  instance_type: g4dn.xlarge
  stack_name: GeuseMaker-dev

app:
  environment: development
  debug: true

services:
  ollama:
    models:
      - llama2:7b  # Smaller model for development
```

### Deployment Types (`config/deployment-types.yml`)

```yaml
spot:
  aws:
    instance_type: g4dn.xlarge
    max_bid_price: 0.50
    interruption_behavior: terminate
  
  app:
    auto_restart: true
    backup_enabled: true

ondemand:
  aws:
    instance_type: g4dn.xlarge
    reliability: high
  
  app:
    auto_restart: false
    backup_enabled: true

simple:
  aws:
    instance_type: g4dn.xlarge
    simplified: true
  
  app:
    auto_restart: false
    backup_enabled: false
```

## Template System

### Environment File Template (`config/templates/environment.yml.j2`)

```jinja2
# Generated environment file for {{ environment }} environment
# Generated on {{ timestamp }}

# AWS Configuration
AWS_REGION={{ aws.region }}
AWS_INSTANCE_TYPE={{ aws.instance_type }}
AWS_KEY_NAME={{ aws.key_name }}
STACK_NAME={{ aws.stack_name }}

# Application Configuration
PROJECT_NAME={{ app.name }}
APP_VERSION={{ app.version }}
APP_PORT={{ app.port }}
APP_ENVIRONMENT={{ app.environment }}
{% if app.debug %}DEBUG=true{% else %}DEBUG=false{% endif %}

# Docker Configuration
DOCKER_REGISTRY={{ docker.registry }}
DOCKER_IMAGE_PREFIX={{ docker.image_prefix }}
COMPOSE_VERSION={{ docker.compose_version }}

# Service Configuration
{% for service_name, service_config in services.items() %}
{% if service_config.enabled %}
{{ service_name.upper() }}_ENABLED=true
{{ service_name.upper() }}_PORT={{ service_config.port }}
{% if service_config.memory_limit %}{{ service_name.upper() }}_MEMORY_LIMIT={{ service_config.memory_limit }}{% endif %}
{% else %}
{{ service_name.upper() }}_ENABLED=false
{% endif %}
{% endfor %}
```

### Docker Compose Template (`config/templates/docker-compose.yml.j2`)

```jinja2
version: '{{ compose_version }}'

services:
{% for service_name, service_config in services.items() %}
{% if service_config.enabled %}
  {{ service_name }}:
    image: {{ docker.registry }}/{{ docker.image_prefix }}/{{ service_name }}:{{ app.version }}
    ports:
      - "{{ service_config.port }}:{{ service_config.port }}"
    environment:
      - SERVICE_NAME={{ service_name }}
      - SERVICE_PORT={{ service_config.port }}
    {% if service_config.memory_limit %}
    deploy:
      resources:
        limits:
          memory: {{ service_config.memory_limit }}
    {% endif %}
    restart: unless-stopped
{% endif %}
{% endfor %}
```

## API Reference

### Core Functions

#### `load_configuration(environment)`

Loads configuration for the specified environment.

```bash
load_configuration "development"
```

#### `get_config_value(path)`

Retrieves a configuration value using dot notation.

```bash
INSTANCE_TYPE=$(get_config_value "aws.instance_type")
REGION=$(get_config_value "aws.region")
```

#### `generate_environment_file(environment, output_file)`

Generates an environment file for the specified environment.

```bash
generate_environment_file "development" ".env"
```

#### `validate_configuration(environment)`

Validates configuration for the specified environment.

```bash
if validate_configuration "production"; then
    echo "Configuration is valid"
else
    echo "Configuration validation failed"
fi
```

#### `apply_environment_overrides(environment)`

Applies environment-specific overrides to the current configuration.

```bash
apply_environment_overrides "production"
```

### Utility Functions

#### `get_deployment_config(deployment_type)`

Gets deployment-specific configuration.

```bash
SPOT_CONFIG=$(get_deployment_config "spot")
```

#### `merge_configurations(base_config, override_config)`

Merges two configuration objects.

```bash
FINAL_CONFIG=$(merge_configurations "$BASE_CONFIG" "$OVERRIDE_CONFIG")
```

#### `validate_yaml_file(file_path)`

Validates YAML file syntax.

```bash
if validate_yaml_file "config/environments/production.yml"; then
    echo "YAML file is valid"
fi
```

## Integration with Existing Scripts

### Automatic Integration

All scripts that use the shared library system automatically benefit from the centralized configuration:

- `aws-deployment-unified.sh`
- `check-instance-status.sh`
- `quick-deploy.sh`
- `cleanup-consolidated.sh`
- `config-manager.sh`

### Backward Compatibility

The system maintains full backward compatibility:

1. **Legacy Mode**: If the configuration management library is not available, scripts fall back to legacy behavior
2. **Environment Variables**: Existing environment variable patterns continue to work
3. **Docker Compose**: Existing Docker Compose files remain compatible

### Migration Guide

#### For Existing Scripts

1. **Automatic**: Scripts using the shared library system are automatically updated
2. **Manual**: For custom scripts, add the following:

```bash
# Load the configuration management system
if [ -f "$LIB_DIR/config-management.sh" ]; then
    source "$LIB_DIR/config-management.sh"
    CONFIG_MANAGEMENT_AVAILABLE=true
else
    CONFIG_MANAGEMENT_AVAILABLE=false
    warning "Centralized configuration management not available, using legacy mode"
fi

# Use configuration values
if [ "$CONFIG_MANAGEMENT_AVAILABLE" = "true" ]; then
    load_configuration "$ENVIRONMENT"
    INSTANCE_TYPE=$(get_config_value "aws.instance_type")
else
    # Legacy fallback
    INSTANCE_TYPE="${INSTANCE_TYPE:-g4dn.xlarge}"
fi
```

## Testing

### Test Suites

1. **Unit Tests** (`tests/test-config-management.sh`)
   - Tests individual functions
   - Validates configuration loading
   - Tests template processing

2. **Integration Tests** (`tests/test-config-integration.sh`)
   - Tests script integration
   - Validates backward compatibility
   - Tests end-to-end workflows

### Running Tests

```bash
# Run configuration management tests
make test:config

# Run integration tests
./tests/test-config-integration.sh

# Run all tests
make test:all
```

## Best Practices

### Configuration Management

1. **Use Hierarchical Structure**: Leverage the inheritance system for clean organization
2. **Environment-Specific Overrides**: Keep environment differences minimal
3. **Validation**: Always validate configuration before deployment
4. **Documentation**: Document any custom configuration values

### Script Development

1. **Use Configuration Functions**: Always use `get_config_value()` instead of hardcoded values
2. **Fallback Gracefully**: Provide sensible defaults for missing configuration
3. **Validate Early**: Validate configuration at script startup
4. **Log Configuration**: Log important configuration values for debugging

### Security Considerations

1. **Sensitive Data**: Never store sensitive data in configuration files
2. **Access Control**: Use AWS Parameter Store or Secrets Manager for secrets
3. **Validation**: Validate all configuration inputs
4. **Audit Trail**: Log configuration changes

## Troubleshooting

### Common Issues

#### Configuration Not Loading

```bash
# Check if configuration files exist
ls -la config/environments/

# Validate YAML syntax
yq eval '.' config/environments/development.yml

# Check library availability
test -f lib/config-management.sh && echo "Library exists" || echo "Library missing"
```

#### Environment Variables Not Set

```bash
# Generate environment file manually
source lib/config-management.sh
generate_environment_file "development" ".env"

# Check generated file
cat .env
```

#### Template Processing Errors

```bash
# Check template syntax
bash -n lib/config-management.sh

# Test template processing
source lib/config-management.sh
load_configuration "development"
process_template "config/templates/environment.yml.j2" "/tmp/test.env"
```

### Debug Mode

Enable debug mode for detailed logging:

```bash
export CONFIG_DEBUG=true
source lib/config-management.sh
load_configuration "development"
```

## Future Enhancements

### Planned Features

1. **Configuration Encryption**: Encrypt sensitive configuration values
2. **Dynamic Configuration**: Support for runtime configuration updates
3. **Configuration UI**: Web-based configuration management interface
4. **Configuration Versioning**: Track configuration changes over time
5. **Multi-Cloud Support**: Extend to support other cloud providers

### Extension Points

The configuration system is designed for extensibility:

1. **Custom Validators**: Add custom validation rules
2. **Template Engines**: Support additional template engines
3. **Configuration Sources**: Add support for external configuration sources
4. **Caching**: Implement configuration caching for performance

## Conclusion

The centralized configuration management system provides a robust, scalable foundation for managing application configuration across all deployment types and environments. It maintains backward compatibility while providing powerful new capabilities for configuration management.

For questions or issues, refer to the test suites or contact the development team. 