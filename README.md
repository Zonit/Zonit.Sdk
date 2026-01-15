# Zonit SDK

Zonit SDK is a comprehensive software development kit that provides a modular architecture for building enterprise-level applications with multi-tenancy, identity management, AI integration, and microservices support.

## 📖 Overview

This repository serves as the main SDK that orchestrates multiple extensions, plugins, and services through Git submodules. Each component is maintained as a separate repository, allowing for independent versioning and development while providing a unified development experience.

## 🏗️ Architecture

The SDK is organized into three main categories:

### Extensions

Modular extensions that add specific functionality to your application:

- **[Zonit.Extensions](https://github.com/Zonit/Zonit.Extensions)** - Core extension framework and base utilities
- **[Zonit.Extensions.Ai](https://github.com/Zonit/Zonit.Extensions.Ai)** - AI and machine learning integration capabilities
- **[Zonit.Extensions.Cultures](https://github.com/Zonit/Zonit.Extensions.Cultures)** - Localization and multi-language support
- **[Zonit.Extensions.Databases](https://github.com/Zonit/Zonit.Extensions.Databases)** - Database abstraction and management
- **[Zonit.Extensions.Identity](https://github.com/Zonit/Zonit.Extensions.Identity)** - Authentication and authorization framework
- **[Zonit.Extensions.Organizations](https://github.com/Zonit/Zonit.Extensions.Organizations)** - Organization structure and hierarchy management
- **[Zonit.Extensions.Projects](https://github.com/Zonit/Zonit.Extensions.Projects)** - Project management and organization
- **[Zonit.Extensions.Tenants](https://github.com/Zonit/Zonit.Extensions.Tenants)** - Multi-tenancy support and tenant isolation

### Plugins

- **[Zonit.Plugins](https://github.com/Zonit/Zonit.Plugins)** - Plugin system for extending application functionality

### Services

Microservices for specific business domains:

- **[Zonit.Services.Dashboard](https://github.com/Zonit/Zonit.Services.Dashboard)** - Dashboard and analytics service
- **[Zonit.Services.EventMessage](https://github.com/Zonit/Zonit.Services.EventMessage)** - Event-driven messaging and communication service

## 🚀 Getting Started

### Prerequisites

- Git 2.13+ (for submodule support)
- .NET SDK (version specified in global.json or Directory.Build.props)
- Visual Studio 2022 or VS Code with C# extension

### Initial Setup

**Option 1 - Clone with automatic submodule initialization (Recommended):**
```powershell
git clone --recurse-submodules https://github.com/Zonit/Zonit.Sdk.git
cd Zonit.Sdk
```

**Option 2 - Clone and run setup script:**
```powershell
git clone https://github.com/Zonit/Zonit.Sdk.git
cd Zonit.Sdk
.\Setup-Repository.ps1
```

**Option 3 - Manual submodule initialization:**
```powershell
git clone https://github.com/Zonit/Zonit.Sdk.git
cd Zonit.Sdk
git submodule update --init --recursive
```

### Global Git Configuration (Recommended)

Configure Git to automatically handle submodules for all operations:
```powershell
git config --global submodule.recurse true
```

This ensures submodules are automatically updated during `git pull`, `git checkout`, and other operations.

## 🔧 Usage

### Building the Solution

```powershell
# Build all projects
dotnet build Zonit.slnx

# Build in Release mode
dotnet build Zonit.slnx -c Release
```

### Running Tests

```powershell
# Run all tests
dotnet test Zonit.slnx

# Run tests with coverage
dotnet test Zonit.slnx --collect:"XPlat Code Coverage"
```

### Updating the SDK

```powershell
# Update main repository and all submodules to latest
git pull --recurse-submodules

# Or use the setup script
.\Setup-Repository.ps1
```

### Working with Individual Submodules

```powershell
# Check status of all submodules
git submodule status

# Update specific submodule to latest remote version
git submodule update --remote Source/Extensions/Zonit.Extensions.Ai

# Execute command in all submodules
git submodule foreach git status
git submodule foreach git pull origin main
```

### Making Changes to Submodules

Each submodule is an independent Git repository. To make changes:

1. Navigate to the submodule directory
2. Create a branch and make your changes
3. Commit and push to the submodule's repository
4. Update the parent repository to reference the new commit

```powershell
# Example: Making changes to Zonit.Extensions.Ai
cd Source/Extensions/Zonit.Extensions.Ai
git checkout -b feature/my-new-feature
# Make your changes
git add .
git commit -m "Add new feature"
git push origin feature/my-new-feature

# Return to main repository and update submodule reference
cd ../../..
git add Source/Extensions/Zonit.Extensions.Ai
git commit -m "Update Zonit.Extensions.Ai submodule"
git push
```

## 📁 Project Structure

```
Zonit.Sdk/
├── Source/
│   ├── Extensions/          # Extension modules
│   │   ├── Zonit.Extensions/
│   │   ├── Zonit.Extensions.Ai/
│   │   ├── Zonit.Extensions.Cultures/
│   │   ├── Zonit.Extensions.Databases/
│   │   ├── Zonit.Extensions.Identity/
│   │   ├── Zonit.Extensions.Organizations/
│   │   ├── Zonit.Extensions.Projects/
│   │   └── Zonit.Extensions.Tenants/
│   ├── Plugins/             # Plugin system
│   │   └── Zonit.Plugins/
│   └── Services/            # Microservices
│       ├── Zonit.Services.Dashboard/
│       └── Zonit.Services.EventMessage/
├── Directory.Build.props    # Common build properties
├── Zonit.slnx              # Solution file
├── Setup-Repository.ps1    # Automated setup script
└── README.md               # This file
```

## 🤝 Contributing

Contributions are welcome! Since this is a multi-repository project:

1. Each submodule has its own repository and contribution guidelines
2. Check the individual repository's README for specific contribution instructions
3. For SDK-level changes, open an issue or PR in this repository

## 📝 License

See [LICENSE.txt](LICENSE.txt) for details.

## 🔗 Related Repositories

All submodules are hosted under the [Zonit GitHub Organization](https://github.com/Zonit).

## ⚙️ Maintenance Scripts

### Setup-Repository.ps1
Initial repository setup and submodule initialization. Automatically downloads all submodules and prepares the workspace.

```powershell
.\Setup-Repository.ps1
```

### Update-ZonitSolution.ps1
Advanced solution file management and maintenance tool. Automatically generates and maintains the Visual Studio solution file with proper project hierarchy based on Git submodules.

📖 **[Full Documentation](README-UpdateZonitSolution.md)**

**Quick usage:**
```powershell
# Preview structure without making changes
.\Update-ZonitSolution.ps1 -DryRun

# Update submodules and rebuild solution
.\Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

**Features:**
- Automatic submodule discovery and grouping by category
- Visual Studio solution generation with hierarchical folder structure
- Submodule update management
- Backup creation before rebuild
- Solution item detection (README, config files, etc.)

## 📚 Documentation

For detailed documentation on each component, please refer to the individual repository's documentation:

- Extensions documentation: See each extension's repository
- Plugin development: [Zonit.Plugins](https://github.com/Zonit/Zonit.Plugins)
- Service APIs: Check individual service repositories

## 🐛 Troubleshooting

### Submodules not initialized
```powershell
git submodule update --init --recursive
```

### Submodules out of sync
```powershell
git submodule sync --recursive
git submodule update --init --recursive
```

### Reset all submodules to tracked commits
```powershell
git submodule foreach --recursive git reset --hard
git submodule update --init --recursive
```