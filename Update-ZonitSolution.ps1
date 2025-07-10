#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automatycznie aktualizuje plik Zonit.sln, dodaj�c wszystkie projekty C# znalezione w submodu�ach Git.

.DESCRIPTION
    Skrypt skanuje wszystkie �cie�ki zdefiniowane w .gitmodules, znajduje pliki .csproj i .vbproj,
    a nast�pnie dodaje je do pliku rozwi�zania Visual Studio z logicznie pogrupowan� struktur� folder�w.

.PARAMETER SolutionPath
    �cie�ka do pliku .sln (domy�lnie "Zonit.sln")

.PARAMETER GitModulesPath
    �cie�ka do pliku .gitmodules (domy�lnie ".gitmodules")

.PARAMETER DryRun
    Je�li ustawione, skrypt tylko wy�wietli co by zosta�o dodane, bez modyfikowania pliku .sln

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

# Funkcja do generowania GUID dla projekt�w
function New-ProjectGuid {
    return [System.Guid]::NewGuid().ToString("B").ToUpper()
}

# Funkcja do parsowania .gitmodules
function Get-GitSubmodules {
    param([string]$GitModulesPath)
    
    if (-not (Test-Path $GitModulesPath)) {
        Write-Error "Plik .gitmodules nie zosta� znaleziony: $GitModulesPath"
        return @()
    }
    
    $content = Get-Content $GitModulesPath -Raw
    $submodules = @()
    
    # Regex do wyci�gni�cia path z ka�dego submodule
    $matches = [regex]::Matches($content, '(?m)^\s*path\s*=\s*(.+)$')
    
    foreach ($match in $matches) {
        $path = $match.Groups[1].Value.Trim()
        if ($path -and $path -ne "") {
            $submodules += $path
        }
    }
    
    # Usu� duplikaty i posortuj
    $uniqueSubmodules = $submodules | Sort-Object | Get-Unique
    
    Write-Host "Znaleziono $($submodules.Count) wpis�w submodu��w, $($uniqueSubmodules.Count) unikalnych" -ForegroundColor Cyan
    
    return $uniqueSubmodules
}

# Funkcja do znajdowania projekt�w w danej �cie�ce
function Find-ProjectsInPath {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Warning "�cie�ka nie istnieje: $Path"
        return @()
    }
    
    $projects = @()
    
    # Znajd� wszystkie pliki projekt�w
    $projectFiles = Get-ChildItem -Path $Path -Recurse -Include "*.csproj", "*.vbproj", "*.fsproj" -ErrorAction SilentlyContinue
    
    foreach ($projectFile in $projectFiles) {
        $relativePath = $projectFile.FullName.Replace((Get-Location).Path, "").TrimStart('\', '/').Replace('/', '\')
        $projectName = $projectFile.BaseName
        
        # Okre�l kategori� projektu na podstawie �cie�ki
        $category = Get-ProjectCategory -Path $relativePath
        
        $projects += @{
            Name = $projectName
            Path = $relativePath
            FullPath = $projectFile.FullName
            Extension = $projectFile.Extension
            Category = $category
            SubmodulePath = $Path
        }
    }
    
    return $projects
}

# Funkcja do okre�lenia kategorii projektu
function Get-ProjectCategory {
    param([string]$Path)
    
    $pathLower = $Path.ToLower()
    
    Write-Host "    DEBUG: Checking path: $pathLower" -ForegroundColor DarkGray
    
    # Mapowanie kategorii na podstawie �cie�ki - poprawione regex
    if ($pathLower -match "[/\\]services[/\\]") {
        Write-Host "    DEBUG: Matched Services" -ForegroundColor DarkGray
        return "Services"
    }
    elseif ($pathLower -match "[/\\]plugins[/\\]") {
        Write-Host "    DEBUG: Matched Plugins" -ForegroundColor DarkGray
        return "Plugins"
    }
    elseif ($pathLower -match "[/\\]extensions[/\\]") {
        Write-Host "    DEBUG: Matched Extensions" -ForegroundColor DarkGray
        return "Extensions"
    }
    elseif ($pathLower -match "[/\\]tests?[/\\]") {
        Write-Host "    DEBUG: Matched Tests" -ForegroundColor DarkGray
        return "Tests"
    }
    elseif ($pathLower -match "[/\\]samples?[/\\]") {
        Write-Host "    DEBUG: Matched Samples" -ForegroundColor DarkGray
        return "Samples"
    }
    elseif ($pathLower -match "[/\\]tools?[/\\]") {
        Write-Host "    DEBUG: Matched Tools" -ForegroundColor DarkGray
        return "Tools"
    }
    else {
        Write-Host "    DEBUG: No match, defaulting to Other" -ForegroundColor DarkGray
        return "Other"
    }
}

# Funkcja do parsowania istniej�cego pliku .sln
function Get-ExistingSolutionItems {
    param([string]$SolutionPath)
    
    if (-not (Test-Path $SolutionPath)) {
        return @{
            Projects = @()
            Folders = @()
        }
    }
    
    $content = Get-Content $SolutionPath -Raw
    
    # Znajd� istniej�ce projekty - poprawiony regex
    $existingProjects = @()
    $projectMatches = [regex]::Matches($content, '(?m)^Project\("([^"]+)"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+"')
    
    foreach ($match in $projectMatches) {
        $projectTypeGuid = $match.Groups[1].Value
        $existingProjects += @{
            TypeGuid = $projectTypeGuid
            Name = $match.Groups[2].Value
            Path = $match.Groups[3].Value
            Guid = $match.Groups[4].Value
            IsFolder = $projectTypeGuid -eq "{2150E333-8FDC-42A3-9474-1A3956D46DE8}"
        }
    }
    
    return @{
        Projects = $existingProjects | Where-Object { -not $_.IsFolder }
        Folders = $existingProjects | Where-Object { $_.IsFolder }
    }
}

# Funkcja do tworzenia logicznej struktury folder�w
function New-LogicalFolderStructure {
    param(
        [array]$Projects,
        [array]$ExistingFolders
    )
    
    $folders = @{}
    $existingFolderNames = $ExistingFolders | ForEach-Object { $_.Name }
    
    # Grupuj projekty wed�ug kategorii
    $projectsByCategory = $Projects | Group-Object Category
    
    foreach ($categoryGroup in $projectsByCategory) {
        $category = $categoryGroup.Name
        $categoryProjects = $categoryGroup.Group
        
        # Sprawd� czy kategoria nie jest pusta
        if ([string]::IsNullOrWhiteSpace($category)) {
            $category = "Other"
            Write-Warning "Znaleziono projekty bez kategorii, przypisano do 'Other'"
        }
        
        # Pomi� je�li folder kategorii ju� istnieje
        if ($existingFolderNames -contains $category) {
            Write-Host "Pomijanie istniej�cego folderu: $category" -ForegroundColor Yellow
            continue
        }
        
        # Dodaj folder g��wnie kategorii
        if (-not $folders.ContainsKey($category)) {
            $folders[$category] = @{
                Name = $category
                Path = $category
                ParentPath = ""
                Guid = New-ProjectGuid
                Level = 0
            }
        }
        
        # Grupuj projekty w kategorii wed�ug submodu��w
        $projectsBySubmodule = $categoryProjects | Group-Object SubmodulePath
        
        foreach ($submoduleGroup in $projectsBySubmodule) {
            $submodulePath = $submoduleGroup.Name
            $submoduleProjects = $submoduleGroup.Group
            
            # Wyci�gnij nazw� submodu�u z �cie�ki
            $submoduleName = ($submodulePath -split '[/\\]')[-1]
            
            # Sprawd� czy nazwa submodu�u nie jest pusta
            if ([string]::IsNullOrWhiteSpace($submoduleName)) {
                $submoduleName = "Unknown"
                Write-Warning "Nie mo�na okre�li� nazwy submodu�u dla �cie�ki: $submodulePath"
            }
            
            # Je�li w kategorii jest wi�cej ni� jeden submodu�, utw�rz podfolder
            if ($projectsBySubmodule.Count -gt 1) {
                $subfolderKey = "$category\$submoduleName"
                
                if (-not $folders.ContainsKey($subfolderKey)) {
                    $folders[$subfolderKey] = @{
                        Name = $submoduleName
                        Path = $subfolderKey
                        ParentPath = $category
                        Guid = New-ProjectGuid
                        Level = 1
                    }
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
        [hashtable]$ExistingItems,
        [switch]$DryRun
    )
    
    # Przygotuj nowe projekty do dodania
    $newProjects = @()
    $newFolders = @()
    
    foreach ($project in $Projects) {
        $exists = $ExistingItems.Projects | Where-Object { $_.Path -eq $project.Path }
        if (-not $exists) {
            $projectGuid = New-ProjectGuid
            $newProjects += @{
                Name = $project.Name
                Path = $project.Path
                Guid = $projectGuid
                Extension = $project.Extension
                Category = $project.Category
                SubmodulePath = $project.SubmodulePath
            }
        }
    }
    
    # Dodaj nowe foldery
    foreach ($folder in $Folders.Values) {
        $exists = $ExistingItems.Folders | Where-Object { $_.Name -eq $folder.Name }
        if (-not $exists) {
            $newFolders += $folder
        }
    }
    
    if ($DryRun) {
        Write-Host "=== DRY RUN - Podgl�d struktury folder�w ===" -ForegroundColor Yellow
        
        Write-Host "Struktura folder�w:" -ForegroundColor Green
        $sortedFolders = $newFolders | Sort-Object Level, Name
        foreach ($folder in $sortedFolders) {
            $indent = "  " * $folder.Level
            Write-Host "$indent- $($folder.Name)" -ForegroundColor Cyan
        }
        
        Write-Host "`nProjekty pogrupowane:" -ForegroundColor Green
        $projectsByCategory = $newProjects | Group-Object Category
        foreach ($categoryGroup in $projectsByCategory) {
            $categoryName = $categoryGroup.Name
            if ([string]::IsNullOrWhiteSpace($categoryName)) {
                $categoryName = "Other"
            }
            Write-Host "  $($categoryName):" -ForegroundColor Cyan
            $projectsBySubmodule = $categoryGroup.Group | Group-Object SubmodulePath
            foreach ($submoduleGroup in $projectsBySubmodule) {
                $submoduleName = ($submoduleGroup.Name -split '[/\\]')[-1]
                if ([string]::IsNullOrWhiteSpace($submoduleName)) {
                    $submoduleName = "Unknown"
                }
                if ($projectsBySubmodule.Count -gt 1) {
                    Write-Host "    $($submoduleName):" -ForegroundColor Yellow
                    foreach ($project in $submoduleGroup.Group) {
                        Write-Host "      - $($project.Name)" -ForegroundColor Gray
                    }
                } else {
                    foreach ($project in $submoduleGroup.Group) {
                        Write-Host "    - $($project.Name)" -ForegroundColor Gray
                    }
                }
            }
        }
        
        Write-Host "`nPodsumowanie: $($newFolders.Count) folder�w, $($newProjects.Count) projekt�w" -ForegroundColor Yellow
        return
    }
    
    if ($newProjects.Count -eq 0 -and $newFolders.Count -eq 0) {
        Write-Host "Wszystkie projekty i foldery s� ju� w pliku rozwi�zania" -ForegroundColor Yellow
        return
    }
    
    # Czytaj plik .sln
    $content = Get-Content $SolutionPath -Raw
    $lines = $content -split "`r?`n"
    
    # Znajd� miejsce do wstawienia nowych projekt�w
    $insertIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^Global$') {
            $insertIndex = $i
            break
        }
    }
    
    if ($insertIndex -eq -1) {
        Write-Error "Nie mo�na znale�� sekcji Global w pliku .sln"
        return
    }
    
    # Przygotuj nowe linie do wstawienia
    $newLines = @()
    
    # Dodaj nowe foldery (sortowane wed�ug poziomu)
    $sortedFolders = $newFolders | Sort-Object Level, Name
    foreach ($folder in $sortedFolders) {
        $newLines += "Project(`"{2150E333-8FDC-42A3-9474-1A3956D46DE8}`") = `"$($folder.Name)`", `"$($folder.Name)`", `"$($folder.Guid)`""
        $newLines += "EndProject"
    }
    
    # Dodaj nowe projekty
    foreach ($project in $newProjects) {
        $projectTypeGuid = "{9A19103F-16F7-4668-BE54-9A1E7A4F7556}" # C# Project
        $newLines += "Project(`"$projectTypeGuid`") = `"$($project.Name)`", `"$($project.Path)`", `"$($project.Guid)`""
        $newLines += "EndProject"
    }
    
    # Wstaw nowe linie
    $updatedLines = $lines[0..($insertIndex-1)] + $newLines + $lines[$insertIndex..($lines.Count-1)]
    
    # Dodaj konfiguracje projekt�w
    $configInserted = $false
    for ($i = 0; $i -lt $updatedLines.Count; $i++) {
        if ($updatedLines[$i] -match 'GlobalSection\(ProjectConfigurationPlatforms\) = postSolution' -and -not $configInserted) {
            $configLines = @()
            foreach ($project in $newProjects) {
                $configLines += "		$($project.Guid).Debug|Any CPU.ActiveCfg = Debug|Any CPU"
                $configLines += "		$($project.Guid).Debug|Any CPU.Build.0 = Debug|Any CPU"
                $configLines += "		$($project.Guid).Release|Any CPU.ActiveCfg = Release|Any CPU"
                $configLines += "		$($project.Guid).Release|Any CPU.Build.0 = Release|Any CPU"
            }
            
            # Znajd� EndGlobalSection i wstaw przed nim
            for ($j = $i + 1; $j -lt $updatedLines.Count; $j++) {
                if ($updatedLines[$j] -match 'EndGlobalSection') {
                    $updatedLines = $updatedLines[0..($j-1)] + $configLines + $updatedLines[$j..($updatedLines.Count-1)]
                    $configInserted = $true
                    break
                }
            }
            break
        }
    }
    
    # Dodaj mapowanie folder�w (NestedProjects)
    $nestedInserted = $false
    for ($i = 0; $i -lt $updatedLines.Count; $i++) {
        if ($updatedLines[$i] -match 'GlobalSection\(NestedProjects\) = preSolution' -and -not $nestedInserted) {
            $nestedLines = @()
            
            # Mapuj projekty do folder�w
            foreach ($project in $newProjects) {
                $category = $project.Category
                $submoduleName = ($project.SubmodulePath -split '[/\\]')[-1]
                
                # Sprawd� czy kategoria nie jest pusta
                if ([string]::IsNullOrWhiteSpace($category)) {
                    $category = "Other"
                }
                
                # Sprawd� czy nazwa submodu�u nie jest pusta
                if ([string]::IsNullOrWhiteSpace($submoduleName)) {
                    $submoduleName = "Unknown"
                }
                
                # Znajd� odpowiedni folder
                $targetFolder = $null
                $projectsByCategory = $newProjects | Where-Object { $_.Category -eq $project.Category }
                $projectsBySubmodule = $projectsByCategory | Group-Object SubmodulePath
                
                if ($projectsBySubmodule.Count -gt 1) {
                    # Projekt idzie do podfolderu submodu�u
                    $subfolderKey = "$category\$submoduleName"
                    $targetFolder = $Folders[$subfolderKey]
                } else {
                    # Projekt idzie bezpo�rednio do folderu kategorii
                    $targetFolder = $Folders[$category]
                }
                
                if ($targetFolder) {
                    $nestedLines += "		$($project.Guid) = $($targetFolder.Guid)"
                }
            }
            
            # Mapuj podfoldery do folder�w g��wnych
            foreach ($folder in $newFolders) {
                if ($folder.ParentPath -ne "") {
                    $parentFolder = $Folders[$folder.ParentPath]
                    if ($parentFolder) {
                        $nestedLines += "		$($folder.Guid) = $($parentFolder.Guid)"
                    }
                }
            }
            
            # Znajd� EndGlobalSection i wstaw przed nim
            for ($j = $i + 1; $j -lt $updatedLines.Count; $j++) {
                if ($updatedLines[$j] -match 'EndGlobalSection') {
                    $updatedLines = $updatedLines[0..($j-1)] + $nestedLines + $updatedLines[$j..($updatedLines.Count-1)]
                    $nestedInserted = $true
                    break
                }
            }
            break
        }
    }
    
    # Je�li sekcja NestedProjects nie istnieje, utw�rz j�
    if (-not $nestedInserted -and ($newFolders.Count -gt 0 -or $newProjects.Count -gt 0)) {
        Write-Host "Dodawanie sekcji NestedProjects..." -ForegroundColor Cyan
        
        $nestedLines = @()
        $nestedLines += "	GlobalSection(NestedProjects) = preSolution"
        
        # Mapuj projekty do folder�w
        foreach ($project in $newProjects) {
            $category = $project.Category
            $submoduleName = ($project.SubmodulePath -split '[/\\]')[-1]
            
            # Sprawd� czy kategoria nie jest pusta
            if ([string]::IsNullOrWhiteSpace($category)) {
                $category = "Other"
            }
            
            # Sprawd� czy nazwa submodu�u nie jest pusta
            if ([string]::IsNullOrWhiteSpace($submoduleName)) {
                $submoduleName = "Unknown"
            }
            
            # Znajd� odpowiedni folder
            $targetFolder = $null
            $projectsByCategory = $newProjects | Where-Object { $_.Category -eq $project.Category }
            $projectsBySubmodule = $projectsByCategory | Group-Object SubmodulePath
            
            if ($projectsBySubmodule.Count -gt 1) {
                # Projekt idzie do podfolderu submodu�u
                $subfolderKey = "$category\$submoduleName"
                $targetFolder = $Folders[$subfolderKey]
            } else {
                # Projekt idzie bezpo�rednio do folderu kategorii
                $targetFolder = $Folders[$category]
            }
            
            if ($targetFolder) {
                $nestedLines += "		$($project.Guid) = $($targetFolder.Guid)"
            }
        }
        
        # Mapuj podfoldery do folder�w g��wnych
        foreach ($folder in $newFolders) {
            if ($folder.ParentPath -ne "") {
                $parentFolder = $Folders[$folder.ParentPath]
                if ($parentFolder) {
                    $nestedLines += "		$($folder.Guid) = $($parentFolder.Guid)"
                }
            }
        }
        
        $nestedLines += "	EndGlobalSection"
        
        # Znajd� miejsce do wstawienia przed EndGlobal
        for ($i = $updatedLines.Count - 1; $i -ge 0; $i--) {
            if ($updatedLines[$i] -match '^EndGlobal$') {
                $updatedLines = $updatedLines[0..($i-1)] + $nestedLines + $updatedLines[$i..($updatedLines.Count-1)]
                break
            }
        }
    }
    
    # Zapisz plik
    $updatedContent = $updatedLines -join "`r`n"
    Set-Content -Path $SolutionPath -Value $updatedContent -Encoding UTF8
    
    Write-Host "Zaktualizowano plik $SolutionPath" -ForegroundColor Green
    Write-Host "Dodano $($newFolders.Count) folder�w i $($newProjects.Count) projekt�w" -ForegroundColor Green
}

# G��wna logika skryptu
try {
    Write-Host "Rozpoczynam aktualizacj� pliku rozwi�zania..." -ForegroundColor Green
    
    # Pobierz list� submodu��w
    $submodules = Get-GitSubmodules -GitModulesPath $GitModulesPath
    
    if ($submodules.Count -eq 0) {
        Write-Warning "Nie znaleziono submodu��w w pliku $GitModulesPath"
        exit 1
    }
    
    Write-Host "Znaleziono $($submodules.Count) submodu��w" -ForegroundColor Cyan
    
    # Znajd� wszystkie projekty
    $allProjects = @()
    foreach ($submodule in $submodules) {
        Write-Host "Skanowanie: $submodule" -ForegroundColor Gray
        $projects = Find-ProjectsInPath -Path $submodule
        $allProjects += $projects
        Write-Host "  Znaleziono $($projects.Count) projekt�w" -ForegroundColor Gray
    }
    
    if ($allProjects.Count -eq 0) {
        Write-Warning "Nie znaleziono �adnych projekt�w w submodu�ach"
        exit 1
    }
    
    Write-Host "��cznie znaleziono $($allProjects.Count) projekt�w" -ForegroundColor Green
    
    # Pogrupuj projekty wed�ug kategorii
    $projectsByCategory = $allProjects | Group-Object Category
    Write-Host "Kategorie projekt�w:" -ForegroundColor Cyan
    foreach ($group in $projectsByCategory) {
        $categoryName = $group.Name
        if ([string]::IsNullOrWhiteSpace($categoryName)) {
            $categoryName = "Other"
        }
        Write-Host "  $($categoryName): $($group.Count) projekt�w" -ForegroundColor Gray
    }
    
    # Pobierz istniej�ce elementy z pliku .sln
    $existingItems = Get-ExistingSolutionItems -SolutionPath $SolutionPath
    Write-Host "Istniej�ce projekty: $($existingItems.Projects.Count)" -ForegroundColor Cyan
    Write-Host "Istniej�ce foldery: $($existingItems.Folders.Count)" -ForegroundColor Cyan
    
    # Utw�rz logiczn� struktur� folder�w
    $folders = New-LogicalFolderStructure -Projects $allProjects -ExistingFolders $existingItems.Folders
    
    # Aktualizuj plik rozwi�zania
    Update-SolutionFile -SolutionPath $SolutionPath -Projects $allProjects -Folders $folders -ExistingItems $existingItems -DryRun:$DryRun
    
    Write-Host "Zako�czono pomy�lnie!" -ForegroundColor Green
    
} catch {
    Write-Error "Wyst�pi� b��d: $($_.Exception.Message)"
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}