#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Automatyczna konfiguracja repozytorium Zonit.Sdk
.DESCRIPTION
    Ten skrypt inicjalizuje i pobiera wszystkie submoduły Git dla projektu Zonit.Sdk
#>

Write-Host "🚀 Inicjalizacja repozytorium Zonit.Sdk..." -ForegroundColor Cyan

# Sprawdź czy jesteś w głównym katalogu repozytorium
if (-not (Test-Path ".gitmodules")) {
    Write-Host "❌ Błąd: Nie znaleziono pliku .gitmodules. Upewnij się, że jesteś w katalogu głównym repozytorium." -ForegroundColor Red
    exit 1
}

# Inicjalizacja i pobranie submodułów
Write-Host "📦 Pobieranie submodułów..." -ForegroundColor Yellow
git submodule update --init --recursive

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Submoduły zostały pomyślnie pobrane!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Status submodułów:" -ForegroundColor Cyan
    git submodule status
} else {
    Write-Host "❌ Wystąpił błąd podczas pobierania submodułów." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🎉 Repozytorium jest gotowe do pracy!" -ForegroundColor Green
