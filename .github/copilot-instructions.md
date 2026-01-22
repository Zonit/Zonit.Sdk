# Zonit SDK - GitHub Copilot Development Guidelines

## 🎯 Podstawowe Zasady

### 1. Dokumentacja w Kodzie
**ZAWSZE** dodawaj XML documentation (`///`) do wszystkich publicznych i internal członków w języku angielskim:

```csharp
/// <summary>
/// Represents a validated email address with domain verification.
/// </summary>
public readonly struct Email : IEquatable<Email>
{
    /// <summary>
    /// Gets the email address value. Never null - returns empty string for default/Empty.
    /// </summary>
    public string Value => _value ?? string.Empty;
}
```

### 2. AOT/Trimming Support (KRYTYCZNE!)

**PODSTAWOWA ZASADA:** Jeśli coś wymaga reflection → **użyj Source Generator!**

❌ **NIE używaj:**
- `[DynamicallyAccessedMembers]` - to sygnał że trzeba Source Generator
- `[UnconditionalSuppressMessage]` - maskowanie problemu
- `Activator.CreateInstance(Type)` - użyj generics lub source generator
- `Assembly.GetTypes()` - użyj source generator z metadata
- Reflection API (`GetMethod`, `GetProperty`, etc.) - użyj source generator
- `MakeGenericType()` - użyj generics z constraints
- LINQ Expressions (`Expression.Compile()`) - użyj source generator

✅ **ZAWSZE używaj:**
- **Source Generators** - dla serializacji, DI, mapping, itp.
- **Generic constraints** (`where T : IMyInterface`) zamiast reflection
- **Static abstracts** (C# 11+) dla polymorphism bez reflection
- **Incremental Source Generators** dla performance

**Przykład - ŹLE vs DOBRZE:**

```csharp
// ❌ ŹLE - używa reflection
[DynamicallyAccessedMembers(DynamicallyAccessedMemberTypes.PublicProperties)]
public class MyClass
{
    public void Process(Type type)
    {
        var instance = Activator.CreateInstance(type);
        var properties = type.GetProperties();
    }
}

// ✅ DOBRZE - Source Generator generuje kod w compile-time
[Generator]
public class MySourceGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        // Generuj kod dla znanych typów
    }
}
```

**JSON Serialization - Source Generator obowiązkowy:**

```csharp
[JsonSourceGenerationOptions(
    WriteIndented = false,
    PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(MyModel))]
[JsonSerializable(typeof(List<MyModel>))]
internal partial class AppJsonSerializerContext : JsonSerializerContext { }

// Użycie:
var json = JsonSerializer.Serialize(model, AppJsonSerializerContext.Default.MyModel);
```

### 3. Mocne Typowanie z ValueObjects

Używaj **ValueObjects** z `Zonit.Extensions` zamiast prymitywnych typów:

| Domain Concept | ValueObject | Walidacja |
|----------------|-------------|-----------|
| Tytuły | `Title` | Max 60 znaków (SEO) |
| Opisy | `Description` | Max 160 znaków (SEO) |
| Treść | `Content` | Bez limitu |
| URL | `Url` | Format URL |
| URL slug | `UrlSlug` | SEO-friendly format |
| Ceny | `Price` | Decimal, non-negative |
| Kwoty | `Money` | Decimal, może być ujemna |
| Kultura | `Culture` | Walidacja CultureInfo |
| Pliki | `Asset` | SHA256 hash, MIME type |
| Rozmiar pliku | `FileSize` | Formatowanie (KB, MB, GB) |
| Kolor | `Color` | OKLCH format |
| Harmonogram | `Schedule` | Binary 16 bytes, cron-like |

**ValueObjects używają TypeConverter - działa z AOT!**

```csharp
// ❌ ŹLE - prymitywne typy
public class Product
{
    public string Title { get; set; } // Brak walidacji!
    public decimal Price { get; set; } // Brak semantyki!
}

// ✅ DOBRZE - ValueObjects
public class Product
{
    public Title Title { get; set; }
    public Price Price { get; set; }
    public UrlSlug Slug { get; set; }
}
```

### 4. Warstwa Abstrakcji (OBOWIĄZKOWE!)

**Każdy extension/plugin MUSI mieć projekt `.Abstractions`:**

```
Zonit.Extensions.YourFeature/
├── Source/
│   ├── Zonit.Extensions.YourFeature/              # Implementacja
│   └── Zonit.Extensions.YourFeature.Abstractions/ # Interfejsy, modele, enums
```

**Co w `.Abstractions`:**
- Wszystkie interfejsy publiczne (`IYourService`)
- Modele danych (`YourModel`)
- Enums i ValueObjects specyficzne dla domeny
- Extension methods dla DI

```csharp
// Zonit.Extensions.YourFeature.Abstractions/IYourService.cs
namespace Zonit.Extensions.YourFeature.Abstractions;

/// <summary>
/// Defines operations for your feature.
/// </summary>
public interface IYourService
{
    /// <summary>
    /// Gets a model by its identifier.
    /// </summary>
    Task<YourModel?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);
}
```

## � Planowanie Zadań

**Każdy problem = osobny task.** Rozdziel pracę na atomowe zadania:

```
✅ DOBRZE:
1. Dodaj interfejs IUserService do Abstractions
2. Implementuj GetByIdAsync w UserService
3. Dodaj unit testy dla GetByIdAsync
4. Dodaj XML documentation dla UserService

❌ ŹLE:
1. Zrób cały UserService z testami
```

Przed rozpoczęciem pracy:
- 📝 Stwórz listę konkretnych zadań (1 problem = 1 task)
- 🎯 Każde zadanie powinno być weryfikowalne
- ✅ Oznaczaj ukończone zadania od razu po zakończeniu
- 🔄 Nie rób kilku rzeczy jednocześnie

## �🔍 Pytania AI

**ZAWSZE pytaj zanim zaimplementujesz** gdy:
- ❓ Nazwa klasy/metody nie jest oczywista
- ❓ Wymagania biznesowe są niejasne
- ❓ Nie wiesz czy użyć istniejącego ValueObject czy stworzyć nowy
- ❓ Struktura katalogów/namespace jest niejasna
- ❓ Nie masz pewności co do warstwy abstrakcji

## ✅ Checklist przed commit

- [ ] XML documentation dla wszystkich publicznych członków
- [ ] **Brak reflection** - jeśli potrzebne, użyj Source Generator
- [ ] **Brak atrybutów AOT** (`[DynamicallyAccessedMembers]`)
- [ ] ValueObjects zamiast prymitywów dla domen
- [ ] Warstwa `.Abstractions` istnieje i poprawnie zorganizowana
- [ ] Nullable reference types poprawnie oznaczone
- [ ] CancellationToken w metodach async
- [ ] JSON serialization używa Source Generator context
- [ ] Brak ostrzeżeń kompilatora (szczególnie AOT/trimming)

## 🔍 Weryfikacja przed zakończeniem pracy

**ZAWSZE przed zakończeniem:**

1. **Kompilacja projektów:**
   ```powershell
   dotnet build
   ```
   - Sprawdź wszystkie projekty w których były zmiany
   - Upewnij się że nie ma błędów kompilacji
   - Sprawdź czy nie ma warnings (szczególnie AOT/trimming)

2. **Analiza wykonanej pracy:**
   - ✅ Czy wszystkie zaplanowane zadania zostały ukończone?
   - ✅ Czy kod jest zgodny z wytycznymi (XML docs, ValueObjects, Abstractions)?
   - ✅ Czy nie zostały pominięte żadne kroki?
   - ✅ Czy zmiany działają poprawnie (kompilacja przeszła)?

3. **Podsumowanie:**
   - Wymień co zostało zrobione
   - Potwierdź że wszystko działa
   - Wskaż ewentualne ostrzeżenia lub uwagi

## 📚 Przykłady

- ValueObjects: [Source/Extensions/Zonit.Extensions/Source/Zonit.Extensions/ValueObjects](../Source/Extensions/Zonit.Extensions/Source/Zonit.Extensions/ValueObjects)
- Dokumentacja: [ValueObjects README](../Source/Extensions/Zonit.Extensions/Source/Zonit.Extensions/ValueObjects/README.md)
