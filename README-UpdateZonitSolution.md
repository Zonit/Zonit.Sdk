# Update-ZonitSolution.ps1

PowerShell script for automatic management of `Zonit.sln` file with projects from Git submodules.

## 🎯 Features

The script automatically:
- Retrieves submodule list from `.gitmodules` file
- Updates submodules to latest versions from main branch (main/master)
- **Groups submodules by category (Extensions, Services, Plugins)**
- Scans directory structure in submodules
- Generates Visual Studio solution file with proper folder hierarchy
- Includes configuration files (README, .gitignore, Directory.Packages.props, etc.)
- Ignores directories defined in .gitignore (bin, obj, .vs, etc.)

## 📂 Generated Structure

```
📁 Extensions (category)
  📁 Zonit.Extensions.Identity (submodule)
    📄 README.md
    📄 .gitignore
    📁 Source
      📄 Directory.Packages.props
      📦 Zonit.Extensions.Identity (PROJECT)
      📦 Zonit.Extensions.Identity.Abstractions (PROJECT)
    📁 Example
      📦 Example.Project (PROJECT)
📁 Services (category)
  📁 Zonit.Services.Dashboard (submodule)
    📄 README.md
    📁 Source
      📦 Projects...
📁 Plugins (category)
  📁 Zonit.Plugins (submodule)
    ...
```

## 🚀 Usage

### Basic Usage
```powershell
# Preview structure only (no changes)
./Update-ZonitSolution.ps1 -DryRun

# Create/update solution file
./Update-ZonitSolution.ps1 -CleanRebuild

# Full update: submodules + rebuild solution
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

### Parameters

| Parameter | Description | Default |
|----------|-------------|---------|
| `-SolutionPath` | Path to solution file | `Zonit.sln` |
| `-GitModulesPath` | Path to .gitmodules file | `.gitmodules` |
| `-DryRun` | Preview only without changes | `false` |
| `-UpdateSubmodules` | Update submodules from remote | `false` |
| `-CleanRebuild` | Rebuild solution from scratch | `false` |

## 📋 Examples

### 1. Initial Setup
```powershell
# Download latest submodule versions and create solution
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

### 2. Daily Usage
```powershell
# Check for changes in submodules
./Update-ZonitSolution.ps1 -DryRun

# Update everything
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

### 3. After Adding New Submodule
```powershell
# Add submodule in Git (e.g., in Extensions category)
git submodule add https://github.com/Zonit/New.Package Source/Extensions/New.Package

# Rebuild solution
./Update-ZonitSolution.ps1 -CleanRebuild
```

## 🗂️ Categories

The script automatically recognizes categories based on submodule path:

| Path | Category |
|------|----------|
| `Source/Extensions/*` | **Extensions** |
| `Source/Services/*` | **Services** |
| `Source/Plugins/*` | **Plugins** |
| Other | **Other** |

This allows better organization when there are many plugins, services, or extensions.

## 🔧 Technical Details

### Detected Solution Items
- `*.md` (README, CHANGELOG, etc.)
- `*.txt` (LICENSE, etc.)
- `.gitignore`, `.gitattributes`
- `Directory.*.props`, `Directory.*.targets`
- `.editorconfig`
- `global.json`
- `nuget.config`

### Ignored Directories
- `.git`, `.vs`, `.vscode`, `.idea`
- `.github`, `.nuget`
- `bin`, `obj`
- `node_modules`, `packages`
- `TestResults`

### Submodule Update Process
- Automatically detects main branch (main/master)
- Uses `git fetch` + `git pull` for updates
- Displays commit hash after update
- Shows if there were changes

## 💾 Backup

Before each solution rebuild (`-CleanRebuild`), the script creates a backup:
```
Zonit.sln.backup
```

## 📝 Notes

1. Run the script from the main repository directory (where `.gitmodules` is located)
2. Make sure you have Git and PowerShell installed
3. On first run, use `-UpdateSubmodules` to download submodule contents

## 🐛 Troubleshooting

### "Missing .gitmodules file"
```powershell
# Check if you're in the main directory
Get-Location
# Should be: C:\...\Zonit.Sdk
```

### "Cannot find project file"
```powershell
# Rebuild solution
./Update-ZonitSolution.ps1 -CleanRebuild
```

### "Submodules are empty"
```powershell
# Initialize and download submodules
git submodule update --init --recursive
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

## 📚 More Information

This script was created to manage the Zonit SDK mono-repo consisting of multiple NuGet packages as Git submodules.

### Repository Structure
```
Zonit.Sdk/
├── .gitmodules
├── Zonit.sln
├── Update-ZonitSolution.ps1
└── Source/
    ├── Extensions/          → Extensions Category
    │   ├── Zonit.Extensions/
    │   ├── Zonit.Extensions.Ai/
    │   ├── Zonit.Extensions.Identity/
    │   └── ...
    ├── Services/            → Services Category
    │   ├── Zonit.Services.Dashboard/
    │   └── ...
    └── Plugins/             → Plugins Category
        └── Zonit.Plugins/
```

Each submodule is a separate Git repository with its own structure:
```
Zonit.Extensions.Identity/
├── README.md
├── .gitignore
├── Source/
│   ├── Directory.Packages.props
│   ├── Zonit.Extensions.Identity/
│   │   └── Zonit.Extensions.Identity.csproj
│   └── Zonit.Extensions.Identity.Abstractions/
│       └── Zonit.Extensions.Identity.Abstractions.csproj
└── Example/
    └── Example/
        └── Example.csproj
```

### Resulting Visual Studio Structure

```
Solution 'Zonit.sln'
├── 📁 Extensions
│   ├── 📁 Zonit.Extensions
│   ├── 📁 Zonit.Extensions.Ai
│   ├── 📁 Zonit.Extensions.Cultures
│   ├── 📁 Zonit.Extensions.Databases
│   ├── 📁 Zonit.Extensions.Identity
│   ├── 📁 Zonit.Extensions.Organizations
│   ├── 📁 Zonit.Extensions.Projects
│   └── 📁 Zonit.Extensions.Tenants
├── 📁 Services
│   ├── 📁 Zonit.Services.Dashboard
│   └── 📁 Zonit.Services.EventMessage
└── 📁 Plugins
    └── 📁 Zonit.Plugins
```

## 🎨 Console Colors

The script uses colored output in PowerShell:
- 🟢 **Green** - success, projects
- 🔵 **Cyan** - headers, main folders
- 🟣 **Magenta** - categories (Extensions, Services, Plugins)
- ⚪ **White** - subfolders
- ⚫ **Gray** - files, details
- 🟡 **Yellow** - warnings, DRY RUN
- 🔴 **Red** - errors
