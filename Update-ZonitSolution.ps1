#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automatycznie aktualizuje plik Zonit.sln, dodaj¹c wszystkie projekty C# znalezione w submodu³ach Git.

.DESCRIPTION
    Skrypt skanuje wszystkie œcie¿ki zdefiniowane w .gitmodules, znajduje pliki .csproj i .vbproj,
    a nastêpnie dodaje je do pliku rozwi¹zania Visual Studio z odpowiednimi folderami rozwi¹zania.

.PARAMETER SolutionPath
    Œcie¿ka do pliku .sln (domyœlnie "Zonit.sln")

.PARAMETER GitModulesPath
    Œcie¿ka do pliku .gitmodules (domyœlnie ".gitmodules")

.PARAMETER DryRun
    Jeœli ustawione, skrypt tylko wyœwietli co by zosta³o dodane, bez modyfikowania pliku .sln

.EXAMPLE
    ./Update-ZonitSolution.ps1
    
.EXAMPLE
    ./Update-ZonitSolution.ps1 -DryRun
    
.EXAMPLE
    ./Update-ZonitSolution.ps1 -SolutionPath "MyProject.sln" -GitModulesPath ".gitmodules"
#>

param(
    [string]$SolutionPath = "Zonit.sln",
    [string]$GitModulesPath = ".gitmodules",
    [switch]$DryRun
)

# Funkcja do generowania GUID dla projektów
function New-ProjectGuid {
    return [System.Guid]::NewGuid().ToString("B").ToUpper()
}

# Funkcja do parsowania .gitmodules
function Get-GitSubmodules {
    param([string]$GitModulesPath)
    
    if (-not (Test-Path $GitModulesPath)) {
        Write-Error "Plik .gitmodules nie zosta³ znaleziony: $GitModulesPath"
        return @()
    }
    
    $content = Get-Content $GitModulesPath -Raw
    $submodules = @()
    
    # Regex do wyci¹gniêcia path z ka¿dego submodule
    $matches = [regex]::Matches($content, '(?m)^\s*path\s*=\s*(.+)$')
    
    foreach ($match in $matches) {
        $path = $match.Groups[1].Value.Trim()
        if ($path) {
            $submodules += $path
        }
    }
    
    return $submodules | Sort-Object | Get-Unique
}

# Funkcja do znajdowania projektów w danej œcie¿ce
function Find-ProjectsInPath {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Warning "Œcie¿ka nie istnieje: $Path"
        return @()
    }
    
    $projects = @()
    
    # ZnajdŸ wszystkie pliki projektów
    $projectFiles = Get-ChildItem -Path $Path -Recurse -Include "*.csproj", "*.vbproj", "*.fsproj" -ErrorAction SilentlyContinue
    
    foreach ($projectFile in $projectFiles) {
        $relativePath = $projectFile.FullName.Replace((Get-Location).Path, "").TrimStart('\', '/')
        $projectName = $projectFile.BaseName
        
        $projects += @{
            Name = $projectName
            Path = $relativePath
            FullPath = $projectFile.FullName
            Extension = $projectFile.Extension
        }
    }
    
    return $projects
}

# Funkcja do tworzenia struktury folderów rozwi¹zania
function Get-SolutionFolderStructure {
    param([array]$Projects)
    
    $folders = @{}
    
    foreach ($project in $Projects) {
        $pathParts = $project.Path.Split('\', '/') | Where-Object { $_ -ne "" }
        
        # Buduj hierarchiê folderów
        for ($i = 0; $i -lt ($pathParts.Count - 1); $i++) {
            $folderPath = ($pathParts[0..$i] -join '\')
            $folderName = $pathParts[$i]
            
            if (-not $folders.ContainsKey($folderPath)) {
                $parentPath = if ($i -eq 0) { "" } else { ($pathParts[0..($i-1)] -join '\') }
                $folders[$folderPath] = @{
                    Name = $folderName
                    Path = $folderPath
                    ParentPath = $parentPath
                    Guid = New-ProjectGuid
                }
            }
        }
    }
    
    return $folders
}

# Funkcja do aktualizacji pliku .sln
function Update-SolutionFile {
    param(
        [string]$SolutionPath,
        [array]$Projects,
        [hashtable]$Folders,
        [switch]$DryRun
    )
    
    if (-not (Test-Path $SolutionPath)) {
        Write-Error "Plik rozwi¹zania nie zosta³ znaleziony: $SolutionPath"
        return
    }
    
    $solutionContent = Get-Content $SolutionPath -Raw
    
    # ZnajdŸ istniej¹ce projekty
    $existingProjects = @()
    $projectMatches = [regex]::Matches($solutionContent, '(?m)^Project\("[^"]+"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)"')
    
    foreach ($match in $projectMatches) {
        $existingProjects += @{
            Name = $match.Groups[1].Value
            Path = $match.Groups[2].Value
            Guid = $match.Groups[3].Value
        }
    }
    
    # Przygotuj nowe projekty do dodania
    $newProjects = @()
    $newFolders = @()
    
    foreach ($project in $Projects) {
        $exists = $existingProjects | Where-Object { $_.Path -eq $project.Path }
        if (-not $exists) {
            $projectGuid = New-ProjectGuid
            $newProjects += @{
                Name = $project.Name
                Path = $project.Path
                Guid = $projectGuid
                Extension = $project.Extension
            }
        }
    }
    
    # Dodaj nowe foldery
    foreach ($folder in $Folders.Values) {
        $exists = $existingProjects | Where-Object { $_.Name -eq $folder.Name -and $_.Path -eq $folder.Name }
        if (-not $exists) {
            $newFolders += $folder
        }
    }
    
    if ($DryRun) {
        Write-Host "=== DRY RUN - Podgl¹d zmian ===" -ForegroundColor Yellow
        Write-Host "Nowe foldery do dodania:" -ForegroundColor Green
        foreach ($folder in $newFolders) {
            Write-Host "  - $($folder.Name) ($($folder.Path))" -ForegroundColor Cyan
        }
        
        Write-Host "Nowe projekty do dodania:" -ForegroundColor Green
        foreach ($project in $newProjects) {
            Write-Host "  - $($project.Name) -> $($project.Path)" -ForegroundColor Cyan
        }
        
        Write-Host "£¹cznie: $($newFolders.Count) folderów, $($newProjects.Count) projektów" -ForegroundColor Yellow
        return
    }
    
    # Aktualizuj plik .sln
    if ($newProjects.Count -gt 0 -or $newFolders.Count -gt 0) {
        $lines = $solutionContent -split "`r?`n"
        $newLines = @()
        $inGlobalSection = $false
        
        foreach ($line in $lines) {
            $newLines += $line
            
            # Dodaj nowe foldery po ostatnim istniej¹cym projekcie
            if ($line -match '^Project\(' -and $newFolders.Count -gt 0) {
                $nextLineIndex = $lines.IndexOf($line) + 1
                if ($nextLineIndex -lt $lines.Count -and $lines[$nextLineIndex] -match '^EndProject') {
                    # Dodaj foldery po tym projekcie
                    foreach ($folder in $newFolders) {
                        $newLines += "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$($folder.Name)`", `"$($folder.Name)`", `"$($folder.Guid)`""
                        $newLines += "EndProject"
                    }
                    $newFolders = @() # Dodano ju¿ wszystkie foldery
                }
            }
            
            # Dodaj nowe projekty po ostatnim istniej¹cym projekcie
            if ($line -match '^EndProject' -and $newProjects.Count -gt 0) {
                foreach ($project in $newProjects) {
                    $projectTypeGuid = "{9A19103F-16F7-4668-BE54-9A1E7A4F7556}" # C# Project
                    $newLines += "Project(`"$projectTypeGuid`") = `"$($project.Name)`", `"$($project.Path)`", `"$($project.Guid)`""
                    $newLines += "EndProject"
                }
                $newProjects = @() # Dodano ju¿ wszystkie projekty
            }
            
            # Dodaj konfiguracje dla nowych projektów
            if ($line -match 'GlobalSection\(ProjectConfigurationPlatforms\)') {
                $inGlobalSection = $true
            }
            
            if ($inGlobalSection -and $line -match 'EndGlobalSection') {
                # Dodaj konfiguracje przed EndGlobalSection
                foreach ($project in $Projects) {
                    $exists = $existingProjects | Where-Object { $_.Path -eq $project.Path }
                    if (-not $exists) {
                        $guid = ($newProjects | Where-Object { $_.Path -eq $project.Path }).Guid
                        if ($guid) {
                            $newLines = $newLines[0..($newLines.Count-2)] + @(
                                "		$guid.Debug|Any CPU.ActiveCfg = Debug|Any CPU",
                                "		$guid.Debug|Any CPU.Build.0 = Debug|Any CPU",
                                "		$guid.Release|Any CPU.ActiveCfg = Release|Any CPU",
                                "		$guid.Release|Any CPU.Build.0 = Release|Any CPU"
                            ) + $newLines[-1]
                        }
                    }
                }
                $inGlobalSection = $false
            }
        }
        
        $updatedContent = $newLines -join "`r`n"
        Set-Content -Path $SolutionPath -Value $updatedContent -Encoding UTF8
        
        Write-Host "Zaktualizowano plik $SolutionPath" -ForegroundColor Green
        Write-Host "Dodano $($newFolders.Count) folderów i $($newProjects.Count) projektów" -ForegroundColor Green
    } else {
        Write-Host "Wszystkie projekty s¹ ju¿ w pliku rozwi¹zania" -ForegroundColor Yellow
    }
}

# G³ówna logika skryptu
try {
    Write-Host "Rozpoczynam aktualizacjê pliku rozwi¹zania..." -ForegroundColor Green
    
    # Pobierz listê submodu³ów
    $submodules = Get-GitSubmodules -GitModulesPath $GitModulesPath
    
    if ($submodules.Count -eq 0) {
        Write-Warning "Nie znaleziono submodu³ów w pliku $GitModulesPath"
        exit 1
    }
    
    Write-Host "Znaleziono $($submodules.Count) submodu³ów" -ForegroundColor Cyan
    
    # ZnajdŸ wszystkie projekty
    $allProjects = @()
    foreach ($submodule in $submodules) {
        Write-Host "Skanowanie: $submodule" -ForegroundColor Gray
        $projects = Find-ProjectsInPath -Path $submodule
        $allProjects += $projects
        Write-Host "  Znaleziono $($projects.Count) projektów" -ForegroundColor Gray
    }
    
    if ($allProjects.Count -eq 0) {
        Write-Warning "Nie znaleziono ¿adnych projektów w submodu³ach"
        exit 1
    }
    
    Write-Host "£¹cznie znaleziono $($allProjects.Count) projektów" -ForegroundColor Green
    
    # Utwórz strukturê folderów
    $folders = Get-SolutionFolderStructure -Projects $allProjects
    
    # Aktualizuj plik rozwi¹zania
    Update-SolutionFile -SolutionPath $SolutionPath -Projects $allProjects -Folders $folders -DryRun:$DryRun
    
    Write-Host "Zakoñczono pomyœlnie!" -ForegroundColor Green
    
} catch {
    Write-Error "Wyst¹pi³ b³¹d: $($_.Exception.Message)"
    exit 1
}