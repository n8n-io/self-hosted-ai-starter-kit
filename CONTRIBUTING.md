# Self-hosted AI Starter Kit - Vision & Contribution Guidelines

Awesome that you're interested in contributing to the Self-hosted AI Starter
Kit! These specific guidelines are in addition to the general [n8n
contribution
guidelines](https://github.com/n8n-io/n8n/blob/master/CONTRIBUTING.md).

## Vision Statement

The Self-hosted AI Starter Kit is designed to be **the fastest path from zero
to working AI workflows** for developers and organizations who want to
experiment with local, private AI solutions. It provides a curated,
pre-configured foundation that "just works" out of the box, enabling users to
focus on building AI workflows rather than wrestling with infrastructure
setup.

## Core Principles

### 1. Simplicity Over Completeness

The starter kit should prioritize ease of use and quick setup over
comprehensive feature coverage. It's better to do fewer things well than to
attempt to solve every possible use case.

### 2. Learning-Focused, Not Production-Ready

This is explicitly a **learning and experimentation platform**. Users should
be able to go from `git clone` to working AI workflows in minutes, not hours.
Production-grade concerns like high availability, advanced security, and
scalability are intentionally out of scope.

### 3. Opinionated but Extensible

We make opinionated choices about the core stack (n8n + Ollama + Qdrant +
PostgreSQL) to reduce decision paralysis, while providing clear paths for
users to extend and customize as they learn.

### 4. Privacy-First Local Development

Everything should work completely offline and locally by default. External
dependencies should be minimal and optional.

## What Belongs in the Starter Kit

### Core Components

- **n8n**: The workflow automation platform
- **Ollama**: Local LLM inference
- **Qdrant**: Vector database for embeddings
- **PostgreSQL**: Persistent data storage
- **Basic networking**: Simple Docker networking to connect components

### Essential Configuration

This includes:
- Pre-configured environment variables with sensible defaults
- Basic Docker Compose profiles for different hardware (CPU, GPU-Nvidia, GPU-AMD)
- Minimal volume mounts for data persistence
- Sample workflow demonstrating the core capabilities

### Getting Started Materials

This includes:
- Clear installation instructions for different platforms
- A demo workflow showcasing AI capabilities
- Basic documentation for accessing local files
- Links to relevant n8n documentation and templates

## What Doesn't Belong in the Starter Kit

### Production Infrastructure

Including:
- Reverse proxies
- SSL/TLS termination
- Load balancers
- Advanced monitoring and logging
- Backup and recovery systems
- Container orchestration beyond basic Docker Compose

### Advanced Networking

Including:
- Custom network configurations
- VPN integrations
- Multiple environment setups
- Advanced security hardening

### Alternative Technology Stacks

Including:
- Different vector databases
- Alternative workflow platforms
- Multiple LLM backends beyond Ollama
- Different databases for the core setup

### Enterprise Features

Including:
- Authentication systems
- Multi-tenancy
- Advanced access controls
- Compliance tooling

## PR specific requirements

- Small PRs Only:
  - Focus on a single feature or fix per PR.
- Typo-Only PRs:
  - Typos are not sufficient justification for a PR and will be rejected.


Remember: **It's better to be an excellent starting point than a mediocre
everything-solution.**
