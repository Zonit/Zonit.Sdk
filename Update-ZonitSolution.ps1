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
        $categoryInfo = Get-ProjectCategory -Path $relativePath
        
        $projects += [PSCustomObject]@{
            Name = $projectName
            Path = $relativePath
            FullPath = $projectFile.FullName
            Extension = $projectFile.Extension
            Category = $categoryInfo.Category
            FolderPath = $categoryInfo.FolderPath
            SubmodulePath = $Path
        }
    }
    
    return $projects
}

# Funkcja do okre�lenia kategorii projektu i tworzenia �cie�ki folderu
function Get-ProjectCategory {
    param([string]$Path)
    
    $pathLower = $Path.ToLower()
    
    Write-Host "    DEBUG: Checking path: $pathLower" -ForegroundColor DarkGray
    
    # Mapowanie kategorii na podstawie �cie�ki - utworz pe�n� �cie�k� folderu
    if ($pathLower -match "source[/\\]services[/\\]([^/\\]+)") {
        $serviceName = $matches[1] -replace "zonit\.services\.", ""
        # Specjalne przypadki
        if ($serviceName -eq "eventmessage") {
            $serviceName = "EventMessage"
        } else {
            # Kapitalizuj pierwsz� liter�
            $serviceName = $serviceName.Substring(0,1).ToUpper() + $serviceName.Substring(1)
        }
        $folderPath = "Source\Services\$serviceName"
        Write-Host "    DEBUG: Matched Services -> $folderPath" -ForegroundColor DarkGray
        return @{
            Category = "Services"
            FolderPath = $folderPath
        }
    }
    elseif ($pathLower -match "source[/\\]plugins[/\\]([^/\\]+)") {
        $pluginName = $matches[1] -replace "zonit\.plugins\.", ""
        # Kapitalizuj pierwsz� liter� lub u�yj nazwy modu�u
        if ($pluginName -eq "zonit.plugins") {
            $pluginName = "Core"
        } else {
            $pluginName = $pluginName.Substring(0,1).ToUpper() + $pluginName.Substring(1)
        }
        $folderPath = "Source\Plugins\$pluginName"
        Write-Host "    DEBUG: Matched Plugins -> $folderPath" -ForegroundColor DarkGray
        return @{
            Category = "Plugins"
            FolderPath = $folderPath
        }
    }
    elseif ($pathLower -match "source[/\\]extensions[/\\]([^/\\]+)") {
        $extensionName = $matches[1] -replace "zonit\.extensions\.", ""
        if ($extensionName -eq "zonit.extensions") {
            $extensionName = "Core"
        } else {
            # Kapitalizuj pierwsz� liter�
            $extensionName = $extensionName.Substring(0,1).ToUpper() + $extensionName.Substring(1)
        }
        $folderPath = "Source\Extensions\$extensionName"
        Write-Host "    DEBUG: Matched Extensions -> $folderPath" -ForegroundColor DarkGray
        return @{
            Category = "Extensions"
            FolderPath = $folderPath
        }
    }
    elseif ($pathLower -match "[/\\]tests?[/\\]") {
        Write-Host "    DEBUG: Matched Tests" -ForegroundColor DarkGray
        return @{
            Category = "Tests"
            FolderPath = "Tests"
        }
    }
    elseif ($pathLower -match "[/\\]samples?[/\\]") {
        Write-Host "    DEBUG: Matched Samples" -ForegroundColor DarkGray
        return @{
            Category = "Samples"
            FolderPath = "Samples"
        }
    }
    elseif ($pathLower -match "[/\\]tools?[/\\]") {
        Write-Host "    DEBUG: Matched Tools" -ForegroundColor DarkGray
        return @{
            Category = "Tools"
            FolderPath = "Tools"
        }
    }
    else {
        Write-Host "    DEBUG: No match, defaulting to Other" -ForegroundColor DarkGray
        return @{
            Category = "Other"
            FolderPath = "Other"
        }
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
    $projectMatches = [regex]::Matches($content, '(?m)^Project\("([^"]+)"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)"')
    
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
    
    # Grupuj projekty wed�ug FolderPath
    $projectsByFolderPath = $Projects | Group-Object FolderPath
    
    foreach ($folderGroup in $projectsByFolderPath) {
        $folderPath = $folderGroup.Name
        $folderProjects = $folderGroup.Group
        
        # Sprawd� czy �cie�ka folderu nie jest pusta
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            $folderPath = "Other"
            Write-Warning "Znaleziono projekty bez �cie�ki folderu, przypisano do 'Other'"
        }
        
        # Podziel �cie�k� na cz�ci (np. "Source\Extensions\Ai" -> ["Source", "Extensions", "Ai"])
        $pathParts = $folderPath -split '[/\\]'
        
        # Utw�rz wszystkie potrzebne foldery w hierarchii
        $currentPath = ""
        $parentPath = ""
        
        for ($i = 0; $i -lt $pathParts.Length; $i++) {
            $pathPart = $pathParts[$i]
            
            if ($i -eq 0) {
                $currentPath = $pathPart
            } else {
                $currentPath = "$parentPath\$pathPart"
            }
            
            # Sprawd� czy folder ju� istnieje w rozwi�zaniu
            if ($existingFolderNames -contains $pathPart) {
                Write-Host "Pomijanie istniej�cego folderu: $pathPart" -ForegroundColor Yellow
                $parentPath = $currentPath
                continue
            }
            
            # Dodaj folder je�li jeszcze nie istnieje
            if (-not $folders.ContainsKey($currentPath)) {
                $folders[$currentPath] = @{
                    Name = $pathPart
                    Path = $currentPath
                    ParentPath = $parentPath
                    Guid = New-ProjectGuid
                    Level = $i
                }
            }
            
            $parentPath = $currentPath
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
            $newProjects += [PSCustomObject]@{
                Name = $project.Name
                Path = $project.Path
                Guid = $projectGuid
                Extension = $project.Extension
                Category = $project.Category
                FolderPath = $project.FolderPath
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
        $projectsByFolderPath = $newProjects | Group-Object FolderPath
        foreach ($folderGroup in $projectsByFolderPath) {
            $folderPath = $folderGroup.Name
            if ([string]::IsNullOrWhiteSpace($folderPath)) {
                $folderPath = "Other"
            }
            Write-Host "  $($folderPath):" -ForegroundColor Cyan
            foreach ($project in $folderGroup.Group) {
                Write-Host "    - $($project.Name)" -ForegroundColor Gray
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
                $folderPath = $project.FolderPath
                
                # Sprawd� czy �cie�ka folderu nie jest pusta
                if ([string]::IsNullOrWhiteSpace($folderPath)) {
                    $folderPath = "Other"
                }
                
                # Znajd� odpowiedni folder (najg��bszy w hierarchii)
                $targetFolder = $Folders[$folderPath]
                
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
            $folderPath = $project.FolderPath
            
            # Sprawd� czy �cie�ka folderu nie jest pusta
            if ([string]::IsNullOrWhiteSpace($folderPath)) {
                $folderPath = "Other"
            }
            
            # Znajd� odpowiedni folder (najg��bszy w hierarchii)
            $targetFolder = $Folders[$folderPath]
            
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
    
    # Pogrupuj projekty wed�ug �cie�ek folder�w
    $projectsByFolderPath = $allProjects | Group-Object FolderPath
    Write-Host "Foldery docelowe:" -ForegroundColor Cyan
    foreach ($group in $projectsByFolderPath) {
        $folderPath = $group.Name
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            $folderPath = "Other"
        }
        Write-Host "  $($folderPath): $($group.Count) projekt�w" -ForegroundColor Gray
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