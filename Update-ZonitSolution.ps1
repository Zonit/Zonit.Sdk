#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automatycznie aktualizuje plik Zonit.sln, dodaj¹c wszystkie projekty C# znalezione w submodu³ach Git.

.DESCRIPTION
    Skrypt skanuje wszystkie œcie¿ki zdefiniowane w .gitmodules, znajduje pliki .csproj i .vbproj,
    a nastêpnie dodaje je do pliku rozwi¹zania Visual Studio z logicznie pogrupowan¹ struktur¹ folderów.

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
        if ($path -and $path -ne "") {
            $submodules += $path
        }
    }
    
    # Usuñ duplikaty i posortuj
    $uniqueSubmodules = $submodules | Sort-Object | Get-Unique
    
    Write-Host "Znaleziono $($submodules.Count) wpisów submodu³ów, $($uniqueSubmodules.Count) unikalnych" -ForegroundColor Cyan
    
    return $uniqueSubmodules
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
        $relativePath = $projectFile.FullName.Replace((Get-Location).Path, "").TrimStart('\', '/').Replace('/', '\')
        $projectName = $projectFile.BaseName
        
        # Okreœl kategoriê projektu na podstawie œcie¿ki
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

# Funkcja do okreœlenia kategorii projektu i tworzenia œcie¿ki folderu
function Get-ProjectCategory {
    param([string]$Path)
    
    $pathLower = $Path.ToLower()
    
    Write-Host "    DEBUG: Checking path: $pathLower" -ForegroundColor DarkGray
    
    # Mapowanie kategorii na podstawie œcie¿ki - utworz pe³n¹ œcie¿kê folderu
    if ($pathLower -match "source[/\\]services[/\\]([^/\\]+)") {
        $serviceName = $matches[1] -replace "zonit\.services\.", ""
        # Specjalne przypadki
        if ($serviceName -eq "eventmessage") {
            $serviceName = "EventMessage"
        } else {
            # Kapitalizuj pierwsz¹ literê
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
        # Kapitalizuj pierwsz¹ literê lub u¿yj nazwy modu³u
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
            # Kapitalizuj pierwsz¹ literê
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

# Funkcja do parsowania istniej¹cego pliku .sln
function Get-ExistingSolutionItems {
    param([string]$SolutionPath)
    
    if (-not (Test-Path $SolutionPath)) {
        return @{
            Projects = @()
            Folders = @()
        }
    }
    
    $content = Get-Content $SolutionPath -Raw
    
    # ZnajdŸ istniej¹ce projekty - poprawiony regex
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

# Funkcja do tworzenia logicznej struktury folderów
function New-LogicalFolderStructure {
    param(
        [array]$Projects,
        [array]$ExistingFolders
    )
    
    $folders = @{}
    $existingFolderNames = $ExistingFolders | ForEach-Object { $_.Name }
    
    # Grupuj projekty wed³ug FolderPath
    $projectsByFolderPath = $Projects | Group-Object FolderPath
    
    foreach ($folderGroup in $projectsByFolderPath) {
        $folderPath = $folderGroup.Name
        $folderProjects = $folderGroup.Group
        
        # SprawdŸ czy œcie¿ka folderu nie jest pusta
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            $folderPath = "Other"
            Write-Warning "Znaleziono projekty bez œcie¿ki folderu, przypisano do 'Other'"
        }
        
        # Podziel œcie¿kê na czêœci (np. "Source\Extensions\Ai" -> ["Source", "Extensions", "Ai"])
        $pathParts = $folderPath -split '[/\\]'
        
        # Utwórz wszystkie potrzebne foldery w hierarchii
        $currentPath = ""
        $parentPath = ""
        
        for ($i = 0; $i -lt $pathParts.Length; $i++) {
            $pathPart = $pathParts[$i]
            
            if ($i -eq 0) {
                $currentPath = $pathPart
            } else {
                $currentPath = "$parentPath\$pathPart"
            }
            
            # SprawdŸ czy folder ju¿ istnieje w rozwi¹zaniu
            if ($existingFolderNames -contains $pathPart) {
                Write-Host "Pomijanie istniej¹cego folderu: $pathPart" -ForegroundColor Yellow
                $parentPath = $currentPath
                continue
            }
            
            # Dodaj folder jeœli jeszcze nie istnieje
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
        Write-Host "=== DRY RUN - Podgl¹d struktury folderów ===" -ForegroundColor Yellow
        
        Write-Host "Struktura folderów:" -ForegroundColor Green
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
        
        Write-Host "`nPodsumowanie: $($newFolders.Count) folderów, $($newProjects.Count) projektów" -ForegroundColor Yellow
        return
    }
    
    if ($newProjects.Count -eq 0 -and $newFolders.Count -eq 0) {
        Write-Host "Wszystkie projekty i foldery s¹ ju¿ w pliku rozwi¹zania" -ForegroundColor Yellow
        return
    }
    
    # Czytaj plik .sln
    $content = Get-Content $SolutionPath -Raw
    $lines = $content -split "`r?`n"
    
    # ZnajdŸ miejsce do wstawienia nowych projektów
    $insertIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^Global$') {
            $insertIndex = $i
            break
        }
    }
    
    if ($insertIndex -eq -1) {
        Write-Error "Nie mo¿na znaleŸæ sekcji Global w pliku .sln"
        return
    }
    
    # Przygotuj nowe linie do wstawienia
    $newLines = @()
    
    # Dodaj nowe foldery (sortowane wed³ug poziomu)
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
    
    # Dodaj konfiguracje projektów
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
            
            # ZnajdŸ EndGlobalSection i wstaw przed nim
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
    
    # Dodaj mapowanie folderów (NestedProjects)
    $nestedInserted = $false
    for ($i = 0; $i -lt $updatedLines.Count; $i++) {
        if ($updatedLines[$i] -match 'GlobalSection\(NestedProjects\) = preSolution' -and -not $nestedInserted) {
            $nestedLines = @()
            
            # Mapuj projekty do folderów
            foreach ($project in $newProjects) {
                $folderPath = $project.FolderPath
                
                # SprawdŸ czy œcie¿ka folderu nie jest pusta
                if ([string]::IsNullOrWhiteSpace($folderPath)) {
                    $folderPath = "Other"
                }
                
                # ZnajdŸ odpowiedni folder (najg³êbszy w hierarchii)
                $targetFolder = $Folders[$folderPath]
                
                if ($targetFolder) {
                    $nestedLines += "		$($project.Guid) = $($targetFolder.Guid)"
                }
            }
            
            # Mapuj podfoldery do folderów g³ównych
            foreach ($folder in $newFolders) {
                if ($folder.ParentPath -ne "") {
                    $parentFolder = $Folders[$folder.ParentPath]
                    if ($parentFolder) {
                        $nestedLines += "		$($folder.Guid) = $($parentFolder.Guid)"
                    }
                }
            }
            
            # ZnajdŸ EndGlobalSection i wstaw przed nim
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
    
    # Jeœli sekcja NestedProjects nie istnieje, utwórz j¹
    if (-not $nestedInserted -and ($newFolders.Count -gt 0 -or $newProjects.Count -gt 0)) {
        Write-Host "Dodawanie sekcji NestedProjects..." -ForegroundColor Cyan
        
        $nestedLines = @()
        $nestedLines += "	GlobalSection(NestedProjects) = preSolution"
        
        # Mapuj projekty do folderów
        foreach ($project in $newProjects) {
            $folderPath = $project.FolderPath
            
            # SprawdŸ czy œcie¿ka folderu nie jest pusta
            if ([string]::IsNullOrWhiteSpace($folderPath)) {
                $folderPath = "Other"
            }
            
            # ZnajdŸ odpowiedni folder (najg³êbszy w hierarchii)
            $targetFolder = $Folders[$folderPath]
            
            if ($targetFolder) {
                $nestedLines += "		$($project.Guid) = $($targetFolder.Guid)"
            }
        }
        
        # Mapuj podfoldery do folderów g³ównych
        foreach ($folder in $newFolders) {
            if ($folder.ParentPath -ne "") {
                $parentFolder = $Folders[$folder.ParentPath]
                if ($parentFolder) {
                    $nestedLines += "		$($folder.Guid) = $($parentFolder.Guid)"
                }
            }
        }
        
        $nestedLines += "	EndGlobalSection"
        
        # ZnajdŸ miejsce do wstawienia przed EndGlobal
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
    Write-Host "Dodano $($newFolders.Count) folderów i $($newProjects.Count) projektów" -ForegroundColor Green
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
    
    # Pogrupuj projekty wed³ug kategorii
    $projectsByCategory = $allProjects | Group-Object Category
    Write-Host "Kategorie projektów:" -ForegroundColor Cyan
    foreach ($group in $projectsByCategory) {
        $categoryName = $group.Name
        if ([string]::IsNullOrWhiteSpace($categoryName)) {
            $categoryName = "Other"
        }
        Write-Host "  $($categoryName): $($group.Count) projektów" -ForegroundColor Gray
    }
    
    # Pogrupuj projekty wed³ug œcie¿ek folderów
    $projectsByFolderPath = $allProjects | Group-Object FolderPath
    Write-Host "Foldery docelowe:" -ForegroundColor Cyan
    foreach ($group in $projectsByFolderPath) {
        $folderPath = $group.Name
        if ([string]::IsNullOrWhiteSpace($folderPath)) {
            $folderPath = "Other"
        }
        Write-Host "  $($folderPath): $($group.Count) projektów" -ForegroundColor Gray
    }
    
    # Pobierz istniej¹ce elementy z pliku .sln
    $existingItems = Get-ExistingSolutionItems -SolutionPath $SolutionPath
    Write-Host "Istniej¹ce projekty: $($existingItems.Projects.Count)" -ForegroundColor Cyan
    Write-Host "Istniej¹ce foldery: $($existingItems.Folders.Count)" -ForegroundColor Cyan
    
    # Utwórz logiczn¹ strukturê folderów
    $folders = New-LogicalFolderStructure -Projects $allProjects -ExistingFolders $existingItems.Folders
    
    # Aktualizuj plik rozwi¹zania
    Update-SolutionFile -SolutionPath $SolutionPath -Projects $allProjects -Folders $folders -ExistingItems $existingItems -DryRun:$DryRun
    
    Write-Host "Zakoñczono pomyœlnie!" -ForegroundColor Green
    
} catch {
    Write-Error "Wyst¹pi³ b³¹d: $($_.Exception.Message)"
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}