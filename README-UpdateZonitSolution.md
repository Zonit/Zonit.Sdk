# Update-ZonitSolution.ps1

Skrypt PowerShell do automatycznego zarz¹dzania plikiem `Zonit.sln` z projektami pobranymi z submodu³ów Git.

## ?? Funkcjonalnoœæ

Skrypt automatycznie:
- Pobiera listê submodu³ów z pliku `.gitmodules`
- Aktualizuje submodu³y do najnowszych wersji z g³ównej ga³êzi (main/master)
- **Grupuje submodu³y wed³ug kategorii (Extensions, Services, Plugins)**
- Skanuje strukturê katalogów w submodu³ach
- Generuje plik solution Visual Studio z prawid³ow¹ hierarchi¹ folderów
- Uwzglêdnia pliki konfiguracyjne (README, .gitignore, Directory.Packages.props, itp.)
- Pomija katalogi zdefiniowane w .gitignore (bin, obj, .vs, itp.)

## ?? Generowana struktura

```
?? Extensions (kategoria)
  ?? Zonit.Extensions.Identity (submodu³)
    ?? README.md
    ?? .gitignore
    ?? Source
      ?? Directory.Packages.props
      ?? Zonit.Extensions.Identity (PROJEKT)
      ?? Zonit.Extensions.Identity.Abstractions (PROJEKT)
    ?? Example
      ?? Example.Project (PROJEKT)
?? Services (kategoria)
  ?? Zonit.Services.Dashboard (submodu³)
    ?? README.md
    ?? Source
      ?? Projekty...
?? Plugins (kategoria)
  ?? Zonit.Plugins (submodu³)
    ...
```

## ?? U¿ycie

### Podstawowe u¿ycie
```powershell
# Tylko podgl¹d struktury (bez zmian)
./Update-ZonitSolution.ps1 -DryRun

# Utworzenie/aktualizacja pliku solution
./Update-ZonitSolution.ps1 -CleanRebuild

# Pe³na aktualizacja: submodu³y + przebudowa solution
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

### Parametry

| Parametr | Opis | Domyœlnie |
|----------|------|-----------|
| `-SolutionPath` | Œcie¿ka do pliku solution | `Zonit.sln` |
| `-GitModulesPath` | Œcie¿ka do pliku .gitmodules | `.gitmodules` |
| `-DryRun` | Tylko podgl¹d bez zmian | `false` |
| `-UpdateSubmodules` | Aktualizuj submodu³y z remote | `false` |
| `-CleanRebuild` | Przebuduj solution od zera | `false` |

## ?? Przyk³ady

### 1. Pierwsza konfiguracja
```powershell
# Pobierz najnowsze wersje submodu³ów i utwórz solution
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

### 2. Codzienne u¿ycie
```powershell
# SprawdŸ czy s¹ zmiany w submodu³ach
./Update-ZonitSolution.ps1 -DryRun

# Aktualizuj wszystko
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

### 3. Po dodaniu nowego submodu³u
```powershell
# Dodaj submodu³ w Git (np. w kategorii Extensions)
git submodule add https://github.com/Zonit/New.Package Source/Extensions/New.Package

# Przebuduj solution
./Update-ZonitSolution.ps1 -CleanRebuild
```

## ??? Kategorie

Skrypt automatycznie rozpoznaje kategorie na podstawie œcie¿ki submodu³u:

| Œcie¿ka | Kategoria |
|---------|-----------|
| `Source/Extensions/*` | **Extensions** |
| `Source/Services/*` | **Services** |
| `Source/Plugins/*` | **Plugins** |
| Inne | **Other** |

To pozwala na lepsz¹ organizacjê gdy bêdzie wiele pluginów, services czy extensions.

## ?? Szczegó³y techniczne

### Wykrywane pliki Solution Items
- `*.md` (README, CHANGELOG, itp.)
- `*.txt` (LICENSE, itp.)
- `.gitignore`, `.gitattributes`
- `Directory.*.props`, `Directory.*.targets`
- `.editorconfig`
- `global.json`
- `nuget.config`

### Pomijane katalogi
- `.git`, `.vs`, `.vscode`, `.idea`
- `.github`, `.nuget`
- `bin`, `obj`
- `node_modules`, `packages`
- `TestResults`

### Aktualizacja submodu³ów
- Automatycznie wykrywa g³ówn¹ ga³¹Ÿ (main/master)
- U¿ywa `git fetch` + `git pull` do aktualizacji
- Wyœwietla hash commita po aktualizacji
- Pokazuje czy by³y zmiany

## ?? Backup

Przed ka¿d¹ przebudow¹ solution (`-CleanRebuild`), skrypt tworzy kopiê zapasow¹:
```
Zonit.sln.backup
```

## ?? Uwagi

1. Uruchom skrypt z katalogu g³ównego repozytorium (tam gdzie jest `.gitmodules`)
2. Upewnij siê ¿e masz zainstalowany Git i PowerShell
3. Przy pierwszym uruchomieniu u¿yj `-UpdateSubmodules` aby pobraæ zawartoœæ submodu³ów

## ?? Rozwi¹zywanie problemów

### "Brak pliku .gitmodules"
```powershell
# SprawdŸ czy jesteœ w katalogu g³ównym
Get-Location
# Powinno byæ: C:\...\Zonit.Sdk
```

### "Nie mo¿na odnaleŸæ pliku projektu"
```powershell
# Przebuduj solution
./Update-ZonitSolution.ps1 -CleanRebuild
```

### "Submodu³y s¹ puste"
```powershell
# Zainicjalizuj i pobierz submodu³y
git submodule update --init --recursive
./Update-ZonitSolution.ps1 -UpdateSubmodules -CleanRebuild
```

## ?? Wiêcej informacji

Skrypt zosta³ stworzony do zarz¹dzania mono-repo Zonit SDK sk³adaj¹cym siê z wielu paczek NuGet jako submodu³y Git.

### Struktura repozytorium
```
Zonit.Sdk/
??? .gitmodules
??? Zonit.sln
??? Update-ZonitSolution.ps1
??? Source/
    ??? Extensions/          ? Kategoria Extensions
    ?   ??? Zonit.Extensions/
    ?   ??? Zonit.Extensions.Ai/
    ?   ??? Zonit.Extensions.Identity/
    ?   ??? ...
    ??? Services/            ? Kategoria Services
    ?   ??? Zonit.Services.Dashboard/
    ?   ??? ...
    ??? Plugins/             ? Kategoria Plugins
        ??? Zonit.Plugins/
```

Ka¿dy submodu³ to osobne repozytorium Git z w³asn¹ struktur¹:
```
Zonit.Extensions.Identity/
??? README.md
??? .gitignore
??? Source/
?   ??? Directory.Packages.props
?   ??? Zonit.Extensions.Identity/
?   ?   ??? Zonit.Extensions.Identity.csproj
?   ??? Zonit.Extensions.Identity.Abstractions/
?       ??? Zonit.Extensions.Identity.Abstractions.csproj
??? Example/
    ??? Example/
        ??? Example.csproj
```

### Wynikowa struktura w Visual Studio

```
Solution 'Zonit.sln'
??? ?? Extensions
?   ??? ?? Zonit.Extensions
?   ??? ?? Zonit.Extensions.Ai
?   ??? ?? Zonit.Extensions.Cultures
?   ??? ?? Zonit.Extensions.Databases
?   ??? ?? Zonit.Extensions.Identity
?   ??? ?? Zonit.Extensions.Organizations
?   ??? ?? Zonit.Extensions.Projects
?   ??? ?? Zonit.Extensions.Tenants
??? ?? Services
?   ??? ?? Zonit.Services.Dashboard
?   ??? ?? Zonit.Services.EventMessage
??? ?? Plugins
    ??? ?? Zonit.Plugins
```

## ?? Kolory w konsoli

Skrypt u¿ywa kolorowego output w PowerShell:
- ?? **Zielony** - sukces, projekty
- ?? **Cyan** - nag³ówki, g³ówne foldery
- ?? **Magenta** - kategorie (Extensions, Services, Plugins)
- ? **Bia³y** - podfoldery
- ? **Szary** - pliki, szczegó³y
- ?? **¯ó³ty** - ostrze¿enia, DRY RUN
- ?? **Czerwony** - b³êdy
