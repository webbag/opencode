Wciel się w rolę eksperta DevOps i specjalisty ds. bezpieczeństwa. Przygotuj szczegółowy plan implementacji (w formacie Markdown) dla konteneryzacji narzędzia OpenCode CLI.

Plan musi opierać się na następujących, głównych założeniach architektury i bezpieczeństwa:

Środowisko i narzędzie: Domyślnym silnikiem jest rootless Podman na systemach Linux Ubuntu 24 Należy wykorzystać jego natywne mechanizmy mapowania użytkowników, unikając problemów z uprawnieniami przy montowaniu wolumenów (bez używania --userns=keep-id).

Podstawa obrazu ma być open code cli oraz git i python, oraz narzędzia do diagnozowania, nmap, ping, ip oraz inne powszechnie używane. Edytor nano. 

Izolacja i bezpieczeństwo (Sandboxing): Kontener musi ograniczać ryzyko ucieczki (container breakout) w przypadku wygenerowania niebezpiecznego kodu przez AI. Należy użyć flag zdejmujących uprawnienia (np. --cap-drop=ALL, no-new-privileges), 

Montowanie wrażliwych plikików hosta (jak ~/.ssh czy ~/.gitconfig) będzie wykonywane w przyszłości w kolejnej wersji - uwzględnij to. Ponieważ pliki z kontenera będą wysyłane do prywatnych repozytorów na github lub w inne miejsca

Wymagania sieciowe: Kontener musi mieć możliwość komunikacji wychodzącej (egress) z zewnętrznymi API modeli językowych (OpenAI, Anthropic, Google, Mistral, OpenCode Zen oraz inne popularne). OpenCode wewnątrz kontenera musi mieć dostęp do interentu.  

Dystrybucja i CI/CD: Kod źródłowy z Containerfile znajduje się na GitHubie. Obrazy mają być budowane i publikowane automatycznie za pomocą GitHub Actions do rejestru GitHub Container Registry (ghcr.io), aby uniknąć limitów pobrań z Docker Hub.

Struktura dokumentu powinna być czytelna i zawierać następujące sekcje: Wymagania, Architektura i Bezpieczeństwo, Implementacja (konkretne komendy do budowy i bezpiecznego uruchomienia z odpowiednimi flagami), Testowanie, CI/CD oraz Utrzymanie - zgodnie z procesem SDLC i nalepszymi praktykami architektonicznymi tego typu rozwiązań. 

Plan implementacji podziel na 4 etapy zwane - SCOPE
Scenariusz, cel, ograniczenia, procedura weryfikacji, eskalacja.

Kod będzie również pisany w 4 etapach SCOPE, plan implementacji ma to uwzgędniać.

Kod ma być dokumentowany. 

