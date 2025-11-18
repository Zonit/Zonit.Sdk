#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automatycznie aktualizuje plik Zonit.sln z projektami z submodułów Git.

.DESCRIPTION
    Tworzy hierarchiczną strukturę w Visual Studio z grupowaniem według kategorii:
    ?? Extensions (kategoria)
      ?? Zonit.Extensions.Identity (submoduł)
        ?? README.md
        ?? Source
          ?? Directory.Packages.props
          ?? Zonit.Extensions.Identity (PROJEKT)
    ?? Services (kategoria)
      ?? Zonit.Services.Dashboard (submoduł)
        ...

.PARAMETER UpdateSubmodules
    Aktualizuje submoduły do najnowszych wersji z remote

.PARAMETER CleanRebuild
    Przebudowuje solution od zera

.PARAMETER DryRun
    Tylko podgląd bez zmian

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
    
    # Mapowanie ścieżek na kategorie
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
    
    Write-Host "?? Znaleziono $($submodules.Count) submodułów" -ForegroundColor Cyan
    return $submodules
}

function Update-GitSubmodules {
    param([array]$SubmodulePaths)
    
    Write-Host "`n?? Aktualizowanie submodułów..." -ForegroundColor Cyan
    
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
                # Wyłącz output z git (zarówno stdout jak stderr)
                $env:GIT_TERMINAL_PROMPT = '0'
                git fetch origin --quiet 2>&1 | Out-Null
                
                # Znajdź główną gałąź (main/master)
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
                    # Sprawdź czy jesteśmy już na tej gałęzi
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
                    Write-Warning "    ??  Nie znaleziono głównej gałęzi"
                }
            } catch {
                Write-Warning "    ??  $($_.Exception.Message)"
            } finally {
                Pop-Location
            }
        }
        
        Write-Host "? Submoduły zaktualizowane" -ForegroundColor Green
    } catch {
        Write-Error "? Błąd podczas aktualizacji: $($_.Exception.Message)"
    }
}

function Get-SubmoduleStructure {
    param(
        [string]$SubmodulePath,
        [string]$SubmoduleName,
        [string]$Category,
        [string]$BasePath  # Dodany parametr - ścieżka do katalogu głównego
    )
    
    if (-not (Test-Path $SubmodulePath)) {
        Write-Warning "⚠️  Brak katalogu: $SubmodulePath"
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
    
    # Główny folder submodułu
    $rootFolder = @{
        Name = $SubmoduleName
        Path = $SubmoduleName
        FullPath = $SubmodulePath
        Guid = New-ProjectGuid
        Level = 0
        ParentGuid = $null
        Category = $Category
    }
    
    # Wzorce plików do uwzględnienia w Solution Items
    $filePatterns = @(
        "*.md", 
        "*.txt", 
        "*.yml",
        "*.yaml",
        "*.ps1",
        ".gitignore", 
        ".gitattributes", 
        "Directory.*.props", 
        "Directory.*.targets",
        ".editorconfig",
        "global.json",
        "nuget.config",
        "LICENSE*"
    )
    
    # Foldery do pominięcia (zgodnie z .gitignore)
    $excludeDirs = @(
        '.git', 
        '.vs', 
        '.vscode',
        '.idea',
        'bin', 
        'obj', 
        'node_modules',
        'packages',
        'TestResults',
        '.nuget'
    )
    
    # Funkcja pomocnicza do konwersji pełnej ścieżki na względną od solution
    function Get-RelativePathFromSolution {
        param([string]$FullPath)
        
        if ($FullPath.StartsWith($BasePath)) {
            $relativePath = $FullPath.Substring($BasePath.Length).TrimStart('\', '/')
            return $relativePath.Replace('/', '\')
        }
        return $FullPath
    }
    
    # Pliki w katalogu głównym submodułu
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
    
    # Pobierz wszystkie projekty z całego submodułu
    $allProjectFiles = Get-ChildItem -Path $SubmodulePath -Recurse -Include "*.csproj" -ErrorAction SilentlyContinue
    
    # Skanuj tylko foldery pierwszego poziomu (Source, Example, Tools, .github, etc.)
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
            
            # Specjalne traktowanie dla .github - skanuj workflows
            if ($dirName -eq ".github") {
                $workflowsPath = Join-Path $dirFullPath "workflows"
                if (Test-Path $workflowsPath) {
                    $workflowsFolder = @{
                        Name = "workflows"
                        Path = "$dirRelPath\workflows"
                        FullPath = $workflowsPath
                        Guid = New-ProjectGuid
                        Level = 2
                        ParentGuid = $folder.Guid
                    }
                    $folders += $workflowsFolder
                    
                    # Pliki workflow
                    foreach ($pattern in $filePatterns) {
                        Get-ChildItem -Path $workflowsPath -Filter $pattern -File -ErrorAction SilentlyContinue | 
                            ForEach-Object {
                                $relativePath = Get-RelativePathFromSolution -FullPath $_.FullName
                                
                                $files += @{
                                    Name = $_.Name
                                    RelativePath = $relativePath
                                    ParentPath = "$dirRelPath\workflows"
                                    ParentGuid = $workflowsFolder.Guid
                                }
                            }
                    }
                }
            }
            
            # Znajdź wszystkie projekty w tym folderze (rekurencyjnie)
            $folderProjects = $allProjectFiles | Where-Object {
                $_.FullName.StartsWith($dirFullPath + "\")
            }
            
            foreach ($projFile in $folderProjects) {
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
    
    # 2. Główne foldery submodułów z Solution Items
    foreach ($struct in $AllStructures) {
        $root = $struct.RootFolder
        if (-not $root) { continue }
        
        $lines += "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$($root.Name)`", `"$($root.Name)`", `"$($root.Guid)`""
        
        # Pliki w głównym folderze
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
    
    # Główne foldery submodułów są zagnieżdżone w folderach kategorii
    foreach ($struct in $AllStructures) {
        $root = $struct.RootFolder
        if (-not $root) { continue }
        
        $categoryFolder = $CategoryFolders[$root.Category]
        if ($categoryFolder) {
            $lines += "`t`t$($root.Guid) = $($categoryFolder.Guid)"
        }
        
        # Podfoldery są zagnieżdżone w swoich folderach nadrzędnych
        foreach ($folder in $struct.Folders) {
            # ParentGuid wskazuje na folder nadrzędny (może być rootFolder lub inny folder)
            $lines += "`t`t$($folder.Guid) = $($folder.ParentGuid)"
        }
        
        # Projekty są zagnieżdżone w odpowiednich folderach
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
    Write-Host "  DRY RUN - Podgląd struktury solution" -ForegroundColor Yellow
    Write-Host "???????????????????????????????????????????????????????" -ForegroundColor Yellow
    Write-Host ""
    
    $totalProjects = 0
    $totalFolders = 0
    $totalFiles = 0
    
    # Grupuj według kategorii
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
            
            # Pliki w głównym folderze
            $rootFiles = $struct.Files | Where-Object { $_.ParentGuid -eq $root.Guid }
            foreach ($file in $rootFiles) {
                Write-Host "    ?? $($file.Name)" -ForegroundColor DarkGray
                $totalFiles++
            }
            
            # Funkcja pomocnicza do rekurencyjnego wyświetlania folderów
            function Show-FolderTree {
                param(
                    [string]$ParentGuid,
                    [int]$Indent,
                    [array]$AllFolders,
                    [array]$AllFiles,
                    [array]$AllProjects
                )
                
                $indentStr = "  " * $Indent
                
                # Foldery bezpośrednio pod tym rodzicem
                $childFolders = $AllFolders | Where-Object { $_.ParentGuid -eq $ParentGuid }
                foreach ($folder in $childFolders) {
                    Write-Host "$indentStr?? $($folder.Name)" -ForegroundColor White
                    $script:totalFolders++
                    
                    # Pliki w tym folderze
                    $folderFiles = $AllFiles | Where-Object { $_.ParentGuid -eq $folder.Guid }
                    foreach ($file in $folderFiles) {
                        Write-Host "$indentStr  ?? $($file.Name)" -ForegroundColor DarkGray
                        $script:totalFiles++
                    }
                    
                    # Projekty w tym folderze
                    $folderProjects = $AllProjects | Where-Object { $_.ParentGuid -eq $folder.Guid }
                    foreach ($project in $folderProjects) {
                        Write-Host "$indentStr  ?? $($project.Name)" -ForegroundColor Green
                        $script:totalProjects++
                    }
                    
                    # Rekurencyjne wyświetlanie podfolderów
                    Show-FolderTree -ParentGuid $folder.Guid -Indent ($Indent + 1) -AllFolders $AllFolders -AllFiles $AllFiles -AllProjects $AllProjects
                }
            }
            
            # Wyświetl foldery pierwszego poziomu i ich zawartość
            Show-FolderTree -ParentGuid $root.Guid -Indent 2 -AllFolders $struct.Folders -AllFiles $struct.Files -AllProjects $struct.Projects
            
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
    Write-Host "`n?? Rozpoczynam aktualizację solution..." -ForegroundColor Green
    
    # 1. Pobierz listę submodułów
    $submodules = Get-GitSubmodules -GitModulesPath $GitModulesPath
    if ($submodules.Count -eq 0) {
        Write-Error "? Nie znaleziono żadnych submodułów"
        exit 1
    }
    
    # 2. Aktualizuj submoduły (jeśli trzeba)
    if ($UpdateSubmodules) {
        Update-GitSubmodules -SubmodulePaths $submodules
    }
    
    # 3. Skanuj strukturę każdego submodułu
    Write-Host "`n?? Skanowanie struktury submodułów..." -ForegroundColor Cyan
    $allStructures = @()
    $categoryFolders = @{
    }
    
    # Pobierz ścieżkę bazową (katalog główny solution)
    $basePath = (Get-Location).Path
    
    foreach ($submodule in $submodules) {
        $name = Split-Path $submodule -Leaf
        $category = Get-CategoryFromPath -SubmodulePath $submodule
        
        # Utwórz folder kategorii jeśli nie istnieje
        if (-not $categoryFolders.ContainsKey($category)) {
            $categoryFolders[$category] = @{
                Name = $category
                Guid = New-ProjectGuid
            }
        }
        
        Write-Host "  ?? $name ($category)" -ForegroundColor Gray
        
        # Przekaż $basePath do funkcji
        $structure = Get-SubmoduleStructure -SubmodulePath $submodule -SubmoduleName $name -Category $category -BasePath $basePath
        
        if ($structure.RootFolder) {
            $allStructures += $structure
            Write-Host "     ? $($structure.Projects.Count) projektów, $($structure.Folders.Count) folderów, $($structure.Files.Count) plików" -ForegroundColor DarkGray
        }
    }
    
    # 4. Wyświetl podgląd lub utwórz plik solution
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
    
    Write-Host "`n? Zakończono!" -ForegroundColor Green
    
} catch {
    Write-host "`n? Błąd: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
