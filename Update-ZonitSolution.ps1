#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automatycznie aktualizuje plik Zonit.sln z projektami z submodu³ów Git.

.DESCRIPTION
    Tworzy hierarchiczn¹ strukturê w Visual Studio z grupowaniem wed³ug kategorii:
    ?? Extensions (kategoria)
      ?? Zonit.Extensions.Identity (submodu³)
        ?? README.md
        ?? Source
          ?? Directory.Packages.props
          ?? Zonit.Extensions.Identity (PROJEKT)
    ?? Services (kategoria)
      ?? Zonit.Services.Dashboard (submodu³)
        ...

.PARAMETER UpdateSubmodules
    Aktualizuje submodu³y do najnowszych wersji z remote

.PARAMETER CleanRebuild
    Przebudowuje solution od zera

.PARAMETER DryRun
    Tylko podgl¹d bez zmian

.EXAMPLE
    ./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
#>

param(
    [string]$SolutionPath = "Zonit.sln",
    [string]$GitModulesPath = ".gitmodules",
    [switch]$DryRun,
    [switch]$UpdateSubmodules,
    [switch]$CleanRebuild
)

$ErrorActionPreference = "Stop"

# ===========================
# FUNKCJE POMOCNICZE
# ===========================

function New-ProjectGuid {
    return [System.Guid]::NewGuid().ToString("B").ToUpper()
}

function Get-CategoryFromPath {
    param([string]$SubmodulePath)
    
    # Mapowanie œcie¿ek na kategorie
    if ($SubmodulePath -match "Source[\\/]Extensions[\\/]") {
        return "Extensions"
    } elseif ($SubmodulePath -match "Source[\\/]Services[\\/]") {
        return "Services"
    } elseif ($SubmodulePath -match "Source[\\/]Plugins[\\/]") {
        return "Plugins"
    } else {
        return "Other"
    }
}

function Get-GitSubmodules {
    param([string]$GitModulesPath)
    
    if (-not (Test-Path $GitModulesPath)) {
        Write-Error "? Brak pliku .gitmodules"
        return @()
    }
    
    $content = Get-Content $GitModulesPath -Raw
    $matches = [regex]::Matches($content, '(?m)^\s*path\s*=\s*(.+)$')
    $submodules = $matches | ForEach-Object { $_.Groups[1].Value.Trim() } | 
        Where-Object { $_ } | 
        Sort-Object -Unique
    
    Write-Host "?? Znaleziono $($submodules.Count) submodu³ów" -ForegroundColor Cyan
    return $submodules
}

function Update-GitSubmodules {
    param([array]$SubmodulePaths)
    
    Write-Host "`n?? Aktualizowanie submodu³ów..." -ForegroundColor Cyan
    
    try {
        git submodule init 2>&1 | Out-Null
        
        foreach ($submodule in $SubmodulePaths) {
            if (-not (Test-Path $submodule)) {
                Write-Warning "??  Brak katalogu: $submodule"
                continue
            }
            
            Write-Host "  ?? $submodule" -ForegroundColor Gray
            Push-Location $submodule
            
            try {
                # Wy³¹cz output z git (zarówno stdout jak stderr)
                $env:GIT_TERMINAL_PROMPT = '0'
                git fetch origin --quiet 2>&1 | Out-Null
                
                # ZnajdŸ g³ówn¹ ga³¹Ÿ (main/master)
                $branch = (git symbolic-ref refs/remotes/origin/HEAD 2>$null) -replace 'refs/remotes/origin/', ''
                
                if (-not $branch) {
                    $branches = git branch -r 2>&1
                    $branch = if ($branches -match 'origin/main') { 
                        'main' 
                    } elseif ($branches -match 'origin/master') { 
                        'master' 
                    } else { 
                        $null 
                    }
                }
                
                if ($branch) {
                    # SprawdŸ czy jesteœmy ju¿ na tej ga³êzi
                    $currentBranch = git branch --show-current 2>&1
                    
                    if ($currentBranch -ne $branch) {
                        git checkout $branch --quiet 2>&1 | Out-Null
                    }
                    
                    $pullResult = git pull origin $branch --quiet 2>&1
                    $hash = git rev-parse --short HEAD 2>&1
                    
                    if ($pullResult -match "Already up to date") {
                        Write-Host "    ? $branch ($hash) - bez zmian" -ForegroundColor DarkGray
                    } else {
                        Write-Host "    ? $branch ($hash) - zaktualizowano" -ForegroundColor Green
                    }
                } else {
                    Write-Warning "    ??  Nie znaleziono g³ównej ga³êzi"
                }
            } catch {
                Write-Warning "    ??  $($_.Exception.Message)"
            } finally {
                Pop-Location
            }
        }
        
        Write-Host "? Submodu³y zaktualizowane" -ForegroundColor Green
    } catch {
        Write-Error "? B³¹d podczas aktualizacji: $($_.Exception.Message)"
    }
}

function Get-SubmoduleStructure {
    param(
        [string]$SubmodulePath,
        [string]$SubmoduleName,
        [string]$Category,
        [string]$BasePath  # Dodany parametr - œcie¿ka do katalogu g³ównego
    )
    
    if (-not (Test-Path $SubmodulePath)) {
        Write-Warning "??  Brak katalogu: $SubmodulePath"
        return @{
            RootFolder = $null
            Folders = @()
            Projects = @()
            Files = @()
            Category = $Category
        }
    }
    
    $folders = @()
    $projects = @()
    $files = @()
    
    # G³ówny folder submodu³u
    $rootFolder = @{
        Name = $SubmoduleName
        Path = $SubmoduleName
        FullPath = $SubmodulePath
        Guid = New-ProjectGuid
        Level = 0
        ParentGuid = $null
        Category = $Category
    }
    
    # Wzorce plików do uwzglêdnienia w Solution Items
    $filePatterns = @(
        "*.md", 
        "*.txt", 
        ".gitignore", 
        ".gitattributes", 
        "Directory.*.props", 
        "Directory.*.targets",
        ".editorconfig",
        "global.json",
        "nuget.config",
        "LICENSE*"
    )
    
    # Foldery do pominiêcia (zgodnie z .gitignore)
    $excludeDirs = @(
        '.git', 
        '.vs', 
        '.vscode',
        '.idea',
        '.github', 
        'bin', 
        'obj', 
        'node_modules',
        'packages',
        'TestResults',
        '.nuget'
    )
    
    # Funkcja pomocnicza do konwersji pe³nej œcie¿ki na wzglêdn¹ od solution
    function Get-RelativePathFromSolution {
        param([string]$FullPath)
        
        if ($FullPath.StartsWith($BasePath)) {
            $relativePath = $FullPath.Substring($BasePath.Length).TrimStart('\', '/')
            return $relativePath.Replace('/', '\')
        }
        return $FullPath
    }
    
    # Pliki w katalogu g³ównym submodu³u
    foreach ($pattern in $filePatterns) {
        Get-ChildItem -Path $SubmodulePath -Filter $pattern -File -ErrorAction SilentlyContinue | 
            ForEach-Object {
                $relativePath = Get-RelativePathFromSolution -FullPath $_.FullName
                
                $files += @{
                    Name = $_.Name
                    RelativePath = $relativePath
                    ParentPath = $SubmoduleName
                    ParentGuid = $rootFolder.Guid
                }
            }
    }
    
    # Pobierz wszystkie projekty z ca³ego submodu³u
    $allProjectFiles = Get-ChildItem -Path $SubmodulePath -Recurse -Include "*.csproj" -ErrorAction SilentlyContinue
    
    # Rekurencyjne skanowanie podfolderów pierwszego poziomu (Source, Example, Tools, etc.)
    Get-ChildItem -Path $SubmodulePath -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notin $excludeDirs } | 
        ForEach-Object {
            $dirName = $_.Name
            $dirFullPath = $_.FullName
            $dirRelPath = "$SubmoduleName\$dirName"
            
            $folder = @{
                Name = $dirName
                Path = $dirRelPath
                FullPath = $dirFullPath
                Guid = New-ProjectGuid
                Level = 1
                ParentGuid = $rootFolder.Guid
            }
            $folders += $folder
            
            # Pliki w tym folderze
            foreach ($pattern in $filePatterns) {
                Get-ChildItem -Path $dirFullPath -Filter $pattern -File -ErrorAction SilentlyContinue | 
                    ForEach-Object {
                        $relativePath = Get-RelativePathFromSolution -FullPath $_.FullName
                        
                        $files += @{
                            Name = $_.Name
                            RelativePath = $relativePath
                            ParentPath = $dirRelPath
                            ParentGuid = $folder.Guid
                        }
                    }
            }
            
            # ZnajdŸ projekty które nale¿¹ do tego folderu
            $folderProjects = $allProjectFiles | Where-Object {
                $_.FullName.StartsWith($dirFullPath + "\")
            }
            
            foreach ($projFile in $folderProjects) {
                # Normalizuj œcie¿kê - u¿yj funkcji pomocniczej
                $projRelPath = Get-RelativePathFromSolution -FullPath $projFile.FullName
                
                $projects += @{
                    Name = $projFile.BaseName
                    RelativePath = $projRelPath
                    ParentPath = $dirRelPath
                    ParentGuid = $folder.Guid
                    Guid = New-ProjectGuid
                }
            }
        }
    
    return @{
        RootFolder = $rootFolder
        Folders = $folders
        Projects = $projects
        Files = $files
        Category = $Category
    }
}

function New-SolutionFile {
    param(
        [string]$SolutionPath,
        [array]$AllStructures,
        [hashtable]$CategoryFolders
    )
    
    Write-Host "`n?? Tworzenie pliku solution..." -ForegroundColor Cyan
    
    $lines = @(
        "Microsoft Visual Studio Solution File, Format Version 12.00",
        "# Visual Studio Version 17",
        "VisualStudioVersion = 17.0.31903.59",
        "MinimumVisualStudioVersion = 10.0.40219.1"
    )
    
    # 1. Foldery kategorii (Extensions, Services, Plugins)
    foreach ($categoryName in ($CategoryFolders.Keys | Sort-Object)) {
        $categoryFolder = $CategoryFolders[$categoryName]
        $lines += "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$categoryName`", `"$categoryName`", `"$($categoryFolder.Guid)`""
        $lines += "EndProject"
    }
    
    # 2. G³ówne foldery submodu³ów z Solution Items
    foreach ($struct in $AllStructures) {
        $root = $struct.RootFolder
        if (-not $root) { continue }
        
        $lines += "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$($root.Name)`", `"$($root.Name)`", `"$($root.Guid)`""
        
        # Pliki w g³ównym folderze
        $rootFiles = $struct.Files | Where-Object { $_.ParentGuid -eq $root.Guid }
        if ($rootFiles) {
            $lines += "`tProjectSection(SolutionItems) = preProject"
            $rootFiles | ForEach-Object { 
                $lines += "`t`t$($_.RelativePath) = $($_.RelativePath)" 
            }
            $lines += "`tEndProjectSection"
        }
        
        $lines += "EndProject"
    }
    
    # 3. Podfoldery z Solution Items
    foreach ($struct in $AllStructures) {
        foreach ($folder in $struct.Folders) {
            $lines += "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$($folder.Name)`", `"$($folder.Name)`", `"$($folder.Guid)`""
            
            # Pliki w tym folderze
            $folderFiles = $struct.Files | Where-Object { $_.ParentGuid -eq $folder.Guid }
            if ($folderFiles) {
                $lines += "`tProjectSection(SolutionItems) = preProject"
                $folderFiles | ForEach-Object { 
                    $lines += "`t`t$($_.RelativePath) = $($_.RelativePath)" 
                }
                $lines += "`tEndProjectSection"
            }
            
            $lines += "EndProject"
        }
    }
    
    # 4. Projekty
    foreach ($struct in $AllStructures) {
        foreach ($project in $struct.Projects) {
            $lines += "Project(`"{9A19103F-16F7-4668-BE54-9A1E7A4F7556}`") = `"$($project.Name)`", `"$($project.RelativePath)`", `"$($project.Guid)`""
            $lines += "EndProject"
        }
    }
    
    # 5. Global Section
    $lines += "Global"
    $lines += "`tGlobalSection(SolutionConfigurationPlatforms) = preSolution"
    $lines += "`t`tDebug|Any CPU = Debug|Any CPU"
    $lines += "`t`tRelease|Any CPU = Release|Any CPU"
    $lines += "`tEndGlobalSection"
    
    # 6. Konfiguracje projektów
    $lines += "`tGlobalSection(ProjectConfigurationPlatforms) = postSolution"
    foreach ($struct in $AllStructures) {
        foreach ($project in $struct.Projects) {
            $lines += "`t`t$($project.Guid).Debug|Any CPU.ActiveCfg = Debug|Any CPU"
            $lines += "`t`t$($project.Guid).Debug|Any CPU.Build.0 = Debug|Any CPU"
            $lines += "`t`t$($project.Guid).Release|Any CPU.ActiveCfg = Release|Any CPU"
            $lines += "`t`t$($project.Guid).Release|Any CPU.Build.0 = Release|Any CPU"
        }
    }
    $lines += "`tEndGlobalSection"
    
    # 7. Nested Projects (hierarchia)
    $lines += "`tGlobalSection(NestedProjects) = preSolution"
    
    # G³ówne foldery submodu³ów s¹ zagnie¿d¿one w folderach kategorii
    foreach ($struct in $AllStructures) {
        $root = $struct.RootFolder
        if (-not $root) { continue }
        
        $categoryFolder = $CategoryFolders[$root.Category]
        if ($categoryFolder) {
            $lines += "`t`t$($root.Guid) = $($categoryFolder.Guid)"
        }
        
        # Podfoldery s¹ zagnie¿d¿one w g³ównym folderze submodu³u
        foreach ($folder in $struct.Folders) {
            $lines += "`t`t$($folder.Guid) = $($root.Guid)"
        }
        
        # Projekty s¹ zagnie¿d¿one w odpowiednich folderach
        foreach ($project in $struct.Projects) {
            $lines += "`t`t$($project.Guid) = $($project.ParentGuid)"
        }
    }
    $lines += "`tEndGlobalSection"
    
    $lines += "`tGlobalSection(SolutionProperties) = preSolution"
    $lines += "`t`tHideSolutionNode = FALSE"
    $lines += "`tEndGlobalSection"
    $lines += "EndGlobal"
    
    # Zapis do pliku
    Set-Content -Path $SolutionPath -Value ($lines -join "`r`n") -Encoding UTF8
    Write-Host "? Utworzono $SolutionPath" -ForegroundColor Green
}

function Show-DryRunPreview {
    param(
        [array]$AllStructures,
        [hashtable]$CategoryFolders
    )
    
    Write-Host "`n" -NoNewline
    Write-Host "???????????????????????????????????????????????????????" -ForegroundColor Yellow
    Write-Host "  DRY RUN - Podgl¹d struktury solution" -ForegroundColor Yellow
    Write-Host "???????????????????????????????????????????????????????" -ForegroundColor Yellow
    Write-Host ""
    
    $totalProjects = 0
    $totalFolders = 0
    $totalFiles = 0
    
    # Grupuj wed³ug kategorii
    $groupedByCategory = $AllStructures | Group-Object -Property { $_.RootFolder.Category }
    
    foreach ($categoryGroup in ($groupedByCategory | Sort-Object Name)) {
        $categoryName = $categoryGroup.Name
        
        Write-Host "?? $categoryName" -ForegroundColor Magenta
        $totalFolders++
        
        foreach ($struct in ($categoryGroup.Group | Sort-Object { $_.RootFolder.Name })) {
            $root = $struct.RootFolder
            if (-not $root) { continue }
            
            Write-Host "  ?? $($root.Name)" -ForegroundColor Cyan
            $totalFolders++
            
            # Pliki w g³ównym folderze
            $rootFiles = $struct.Files | Where-Object { $_.ParentGuid -eq $root.Guid }
            foreach ($file in $rootFiles) {
                Write-Host "    ?? $($file.Name)" -ForegroundColor DarkGray
                $totalFiles++
            }
            
            # Podfoldery
            foreach ($folder in $struct.Folders) {
                Write-Host "    ?? $($folder.Name)" -ForegroundColor White
                $totalFolders++
                
                # Pliki w folderze
                $folderFiles = $struct.Files | Where-Object { $_.ParentGuid -eq $folder.Guid }
                foreach ($file in $folderFiles) {
                    Write-Host "      ?? $($file.Name)" -ForegroundColor DarkGray
                    $totalFiles++
                }
                
                # Projekty w folderze
                $folderProjects = $struct.Projects | Where-Object { $_.ParentGuid -eq $folder.Guid }
                foreach ($project in $folderProjects) {
                    Write-Host "      ?? $($project.Name)" -ForegroundColor Green
                    $totalProjects++
                }
            }
            
            Write-Host ""
        }
    }
    
    Write-Host "???????????????????????????????????????????????????????" -ForegroundColor Yellow
    Write-Host "?? Podsumowanie:" -ForegroundColor Cyan
    Write-Host "   Projekty:       $totalProjects" -ForegroundColor White
    Write-Host "   Foldery:        $totalFolders" -ForegroundColor White
    Write-Host "   Pliki solution: $totalFiles" -ForegroundColor White
    Write-Host "???????????????????????????????????????????????????????" -ForegroundColor Yellow
}

# ===========================
# MAIN SCRIPT
# ===========================

try {
    Write-Host "`n?? Rozpoczynam aktualizacjê solution..." -ForegroundColor Green
    
    # 1. Pobierz listê submodu³ów
    $submodules = Get-GitSubmodules -GitModulesPath $GitModulesPath
    if ($submodules.Count -eq 0) {
        Write-Error "? Nie znaleziono ¿adnych submodu³ów"
        exit 1
    }
    
    # 2. Aktualizuj submodu³y (jeœli trzeba)
    if ($UpdateSubmodules) {
        Update-GitSubmodules -SubmodulePaths $submodules
    }
    
    # 3. Skanuj strukturê ka¿dego submodu³u
    Write-Host "`n?? Skanowanie struktury submodu³ów..." -ForegroundColor Cyan
    $allStructures = @()
    $categoryFolders = @{
    }
    
    # Pobierz œcie¿kê bazow¹ (katalog g³ówny solution)
    $basePath = (Get-Location).Path
    
    foreach ($submodule in $submodules) {
        $name = Split-Path $submodule -Leaf
        $category = Get-CategoryFromPath -SubmodulePath $submodule
        
        # Utwórz folder kategorii jeœli nie istnieje
        if (-not $categoryFolders.ContainsKey($category)) {
            $categoryFolders[$category] = @{
                Name = $category
                Guid = New-ProjectGuid
            }
        }
        
        Write-Host "  ?? $name ($category)" -ForegroundColor Gray
        
        # Przeka¿ $basePath do funkcji
        $structure = Get-SubmoduleStructure -SubmodulePath $submodule -SubmoduleName $name -Category $category -BasePath $basePath
        
        if ($structure.RootFolder) {
            $allStructures += $structure
            Write-Host "     ? $($structure.Projects.Count) projektów, $($structure.Folders.Count) folderów, $($structure.Files.Count) plików" -ForegroundColor DarkGray
        }
    }
    
    # 4. Wyœwietl podgl¹d lub utwórz plik solution
    if ($DryRun) {
        Show-DryRunPreview -AllStructures $allStructures -CategoryFolders $categoryFolders
        return
    }
    
    # 5. Utwórz backup i nowy plik solution
    if ($CleanRebuild -or -not (Test-Path $SolutionPath)) {
        if (Test-Path $SolutionPath) {
            $backupPath = "$SolutionPath.backup"
            Copy-Item $SolutionPath $backupPath -Force
            Write-Host "?? Kopia zapasowa: $backupPath" -ForegroundColor Yellow
        }
        
        New-SolutionFile -SolutionPath $SolutionPath -AllStructures $allStructures -CategoryFolders $categoryFolders
    }
    
    Write-Host "`n? Zakoñczono!" -ForegroundColor Green
    
} catch {
    Write-host "`n? B³¹d: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
