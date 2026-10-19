import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CorpusEntry: Encodable {
    let file: String
    let category: String
    let language: String
    let scale: Double
    let dark: Bool
    let groundTruth: String
}

struct Sample {
    let category: String
    let lines: [String]
    let fontSize: CGFloat
}

struct LanguageSpec {
    let tag: String
    let font: String
    let samples: [Sample]
}

let languageSpecs = [
    LanguageSpec(tag: "en-US", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Project library", "Search your notes", "Recent captures", "Open folder", "Saved just now"], fontSize: 22),
        Sample(category: "ui", lines: ["Quick note", "Add a heading", "Start a session", "Cancel     Save note", "Changes are synced"], fontSize: 22),
        Sample(category: "code", lines: ["// Keep the newest capture", "struct CaptureRecord {", "    let title: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let recent = loadRecords()", "    return recent.sorted { $0.date > $1.date }", "}"], fontSize: 18),
        Sample(category: "docs", lines: ["A clearer view of the work", "Capture useful details while they are fresh.", "Small observations can connect distant ideas.", "Review these notes before the next session."], fontSize: 21),
        Sample(category: "docs", lines: ["Project notes", "Use a short title for each new thought.", "Keep related decisions in the same section.", "Updated October 19, 2026"], fontSize: 21),
        Sample(category: "chat", lines: ["Mira  09:42", "The new capture flow is ready to review.", "Jon  09:46", "I will test it after the design check."], fontSize: 21),
        Sample(category: "chat", lines: ["Team channel  #planning", "Mira: Please keep the first screen simple.", "Jon: The table now includes source links.", "2 replies     Add a reaction"], fontSize: 21),
        Sample(category: "table", lines: ["Item        Count        Status", "Drafts      12           Ready", "Images      4            Review", "Exports     2            Complete"], fontSize: 20),
        Sample(category: "table", lines: ["Task        Owner        Due", "OCR review  Mira         Today", "CI runner   Jon          Friday", "Release     Team         Oct 28"], fontSize: 20)
    ]),
    LanguageSpec(tag: "de-DE", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Projektbibliothek", "Notizen durchsuchen", "Letzte Aufnahmen", "Ordner öffnen", "Gerade gespeichert"], fontSize: 22),
        Sample(category: "ui", lines: ["Schnelle Notiz", "Überschrift hinzufügen", "Sitzung starten", "Abbrechen     Notiz speichern", "Änderungen synchronisiert"], fontSize: 22),
        Sample(category: "code", lines: ["// Neueste Aufnahme behalten", "struct CaptureRecord {", "    let titel: String", "    func speichern() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let aktuell = ladeEintraege()", "    return aktuell.sorted { $0.datum > $1.datum }", "}"], fontSize: 18),
        Sample(category: "docs", lines: ["Ein klarer Blick auf die Arbeit", "Nützliche Details festhalten, solange sie frisch sind.", "Kleine Beobachtungen verbinden entfernte Ideen.", "Vor der nächsten Sitzung diese Notizen lesen."], fontSize: 20),
        Sample(category: "docs", lines: ["Projektnotizen", "Für jeden neuen Gedanken einen kurzen Titel nutzen.", "Verwandte Entscheidungen im selben Abschnitt halten.", "Aktualisiert am 19. Oktober 2026"], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Der neue Ablauf kann jetzt geprüft werden.", "Jon  09:46", "Ich teste ihn nach der Designrunde."], fontSize: 21),
        Sample(category: "chat", lines: ["Teamkanal  #planung", "Mira: Bitte den ersten Bildschirm einfach halten.", "Jon: Die Tabelle enthält jetzt Quellenlinks.", "2 Antworten     Reaktion hinzufügen"], fontSize: 20),
        Sample(category: "table", lines: ["Eintrag       Anzahl       Status", "Entwürfe      12           Bereit", "Bilder        4            Prüfung", "Exporte       2            Fertig"], fontSize: 20),
        Sample(category: "table", lines: ["Aufgabe       Person       Termin", "OCR-Prüfung   Mira         Heute", "CI-Läufer     Jon          Freitag", "Veröffentlichung Team       28. Okt."], fontSize: 19)
    ]),
    LanguageSpec(tag: "fr-FR", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Bibliothèque de projets", "Rechercher des notes", "Captures récentes", "Ouvrir le dossier", "Enregistré à l’instant"], fontSize: 21),
        Sample(category: "ui", lines: ["Note rapide", "Ajouter un titre", "Démarrer une session", "Annuler     Enregistrer", "Modifications synchronisées"], fontSize: 22),
        Sample(category: "code", lines: ["// Garder la capture récente", "struct CaptureRecord {", "    let titre: String", "    func sauver() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let recentes = chargerNotes()", "    return recentes.sorted { $0.date > $1.date }", "}"], fontSize: 18),
        Sample(category: "docs", lines: ["Une vue plus claire du travail", "Noter les détails utiles pendant qu’ils sont frais.", "De petites observations relient des idées lointaines.", "Relire ces notes avant la prochaine session."], fontSize: 20),
        Sample(category: "docs", lines: ["Notes du projet", "Choisir un titre court pour chaque idée.", "Garder les décisions liées dans la même section.", "Mis à jour le 19 octobre 2026"], fontSize: 21),
        Sample(category: "chat", lines: ["Mira  09:42", "Le nouveau parcours est prêt à être vérifié.", "Jon  09:46", "Je le teste après la revue du design."], fontSize: 21),
        Sample(category: "chat", lines: ["Canal équipe  #planning", "Mira : Gardons le premier écran simple.", "Jon : Le tableau contient les liens sources.", "2 réponses     Ajouter une réaction"], fontSize: 20),
        Sample(category: "table", lines: ["Élément       Nombre       État", "Brouillons    12           Prêt", "Images        4            À revoir", "Exports       2            Terminé"], fontSize: 20),
        Sample(category: "table", lines: ["Tâche         Responsable  Échéance", "Revue OCR     Mira         Aujourd’hui", "Runner CI     Jon          Vendredi", "Publication   Équipe       28 oct."], fontSize: 19)
    ]),
    LanguageSpec(tag: "es-ES", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Biblioteca de proyectos", "Buscar en las notas", "Capturas recientes", "Abrir carpeta", "Guardado ahora mismo"], fontSize: 22),
        Sample(category: "ui", lines: ["Nota rápida", "Añadir un encabezado", "Iniciar sesión", "Cancelar     Guardar nota", "Cambios sincronizados"], fontSize: 22),
        Sample(category: "code", lines: ["// Conservar la captura reciente", "struct CaptureRecord {", "    let titulo: String", "    func guardar() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let recientes = cargarNotas()", "    return recientes.sorted { $0.fecha > $1.fecha }", "}"], fontSize: 18),
        Sample(category: "docs", lines: ["Una vista más clara del trabajo", "Guarda detalles útiles mientras estén recientes.", "Pequeñas observaciones conectan ideas lejanas.", "Revisa estas notas antes de la próxima sesión."], fontSize: 20),
        Sample(category: "docs", lines: ["Notas del proyecto", "Usa un título breve para cada idea nueva.", "Mantén las decisiones relacionadas en una sección.", "Actualizado el 19 de octubre de 2026"], fontSize: 21),
        Sample(category: "chat", lines: ["Mira  09:42", "El nuevo flujo ya está listo para revisar.", "Jon  09:46", "Lo probaré después de revisar el diseño."], fontSize: 21),
        Sample(category: "chat", lines: ["Canal del equipo  #planificación", "Mira: Mantengamos simple la primera pantalla.", "Jon: La tabla ya incluye enlaces de origen.", "2 respuestas     Añadir una reacción"], fontSize: 20),
        Sample(category: "table", lines: ["Elemento      Cantidad     Estado", "Borradores    12           Listo", "Imágenes      4            Revisar", "Exportaciones 2            Completo"], fontSize: 20),
        Sample(category: "table", lines: ["Tarea         Responsable  Fecha", "Revisión OCR  Mira         Hoy", "Runner CI     Jon          Viernes", "Lanzamiento   Equipo       28 oct."], fontSize: 19)
    ]),
    LanguageSpec(tag: "it-IT", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Libreria progetti", "Cerca nelle note", "Acquisizioni recenti", "Apri cartella", "Salvato adesso"], fontSize: 22),
        Sample(category: "code", lines: ["// Conserva la nota recente", "struct CaptureRecord {", "    let titolo: String", "    func salva() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Una visione più chiara del lavoro", "Salva i dettagli utili mentre sono recenti.", "Piccole osservazioni collegano idee lontane.", "Rivedi queste note prima della prossima sessione."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Il nuovo flusso è pronto per la revisione.", "Jon  09:46", "Lo proverò dopo il controllo del design."], fontSize: 21),
        Sample(category: "table", lines: ["Attività      Responsabile  Scadenza", "Revisione OCR Mira          Oggi", "Runner CI    Jon           Venerdì", "Rilascio      Team          28 ott."], fontSize: 19)
    ]),
    LanguageSpec(tag: "pt-BR", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Biblioteca de projetos", "Pesquisar notas", "Capturas recentes", "Abrir pasta", "Salvo agora"], fontSize: 22),
        Sample(category: "code", lines: ["// Mantenha a captura recente", "struct CaptureRecord {", "    let titulo: String", "    func salvar() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Uma visão mais clara do trabalho", "Registre detalhes úteis enquanto estão recentes.", "Pequenas observações conectam ideias distantes.", "Revise estas notas antes da próxima sessão."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "O novo fluxo está pronto para revisão.", "Jon  09:46", "Vou testá-lo após revisar o design."], fontSize: 21),
        Sample(category: "table", lines: ["Tarefa        Responsável  Prazo", "Revisão OCR   Mira         Hoje", "Runner CI     Jon          Sexta", "Lançamento    Equipe       28 out."], fontSize: 19)
    ]),
    LanguageSpec(tag: "vi-VT", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Thư viện dự án", "Tìm kiếm ghi chú", "Bản chụp gần đây", "Mở thư mục", "Đã lưu ngay bây giờ"], fontSize: 21),
        Sample(category: "code", lines: ["// Giữ lại bản chụp mới nhất", "struct CaptureRecord {", "    let tieuDe: String", "    func save() { writeVault() }", "}"], fontSize: 18),
        Sample(category: "docs", lines: ["Nhìn rõ hơn về công việc", "Ghi lại chi tiết hữu ích khi chúng còn mới.", "Quan sát nhỏ có thể kết nối ý tưởng xa nhau.", "Xem lại ghi chú trước phiên làm việc tiếp theo."], fontSize: 19),
        Sample(category: "chat", lines: ["Mira  09:42", "Quy trình mới đã sẵn sàng để xem xét.", "Jon  09:46", "Tôi sẽ thử sau khi kiểm tra thiết kế."], fontSize: 20),
        Sample(category: "table", lines: ["Nhiệm vụ     Người phụ trách  Hạn chót", "Kiểm tra OCR Mira             Hôm nay", "Runner CI    Jon              Thứ Sáu", "Phát hành    Nhóm             28 tháng 10"], fontSize: 18)
    ]),
    LanguageSpec(tag: "tr-TR", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Proje kitaplığı", "Notlarda ara", "Son yakalamalar", "Klasörü aç", "Az önce kaydedildi"], fontSize: 22),
        Sample(category: "code", lines: ["// En yeni yakalamayı koru", "struct CaptureRecord {", "    let baslik: String", "    func kaydet() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Çalışmaya daha net bir bakış", "Yararlı ayrıntıları tazeyken kaydedin.", "Küçük gözlemler uzak fikirleri birleştirir.", "Sonraki oturumdan önce bu notları inceleyin."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Yeni akış gözden geçirmeye hazır.", "Jon  09:46", "Tasarım kontrolünden sonra deneyeceğim."], fontSize: 21),
        Sample(category: "table", lines: ["Görev         Sorumlu      Tarih", "OCR inceleme  Mira         Bugün", "CI runner     Jon          Cuma", "Yayın         Ekip         28 Eki."], fontSize: 20)
    ]),
    LanguageSpec(tag: "id-ID", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Pustaka proyek", "Cari catatan", "Tangkapan terbaru", "Buka folder", "Disimpan barusan"], fontSize: 22),
        Sample(category: "code", lines: ["// Simpan tangkapan terbaru", "struct CaptureRecord {", "    let judul: String", "    func simpan() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Lihat pekerjaan dengan lebih jelas", "Catat detail berguna selagi masih baru.", "Pengamatan kecil menghubungkan ide yang jauh.", "Tinjau catatan ini sebelum sesi berikutnya."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Alur baru siap untuk ditinjau.", "Jon  09:46", "Saya akan mengujinya setelah cek desain."], fontSize: 21),
        Sample(category: "table", lines: ["Tugas         Penanggung jawab  Tenggat", "Tinjauan OCR  Mira              Hari ini", "Runner CI     Jon               Jumat", "Rilis         Tim               28 Okt"], fontSize: 18)
    ]),
    LanguageSpec(tag: "cs-CZ", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Knihovna projektů", "Hledat v poznámkách", "Nedávné záznamy", "Otevřít složku", "Právě uloženo"], fontSize: 21),
        Sample(category: "code", lines: ["// Zachovat nejnovější záznam", "struct CaptureRecord {", "    let nazev: String", "    func ulozit() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Jasnější pohled na práci", "Užitečné podrobnosti zapisujte čerstvé.", "Drobné postřehy propojují vzdálené nápady.", "Před další relací si tyto poznámky projděte."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Nový postup je připraven ke kontrole.", "Jon  09:46", "Otestuji ho po kontrole návrhu."], fontSize: 21),
        Sample(category: "table", lines: ["Úkol          Odpovědná osoba  Termín", "Kontrola OCR  Mira              Dnes", "CI runner     Jon               Pátek", "Vydání        Tým               28. říj."], fontSize: 18)
    ]),
    LanguageSpec(tag: "da-DK", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Projektbibliotek", "Søg i noter", "Seneste optagelser", "Åbn mappe", "Gemt lige nu"], fontSize: 22),
        Sample(category: "code", lines: ["// Behold den nyeste optagelse", "struct CaptureRecord {", "    let titel: String", "    func gem() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Et klarere blik på arbejdet", "Gem nyttige detaljer, mens de er friske.", "Små observationer forbinder fjerne idéer.", "Læs noterne før næste session."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Det nye forløb er klar til gennemgang.", "Jon  09:46", "Jeg tester det efter designtjekket."], fontSize: 21),
        Sample(category: "table", lines: ["Opgave        Ansvarlig    Frist", "OCR-gennemgang Mira        I dag", "CI-runner     Jon          Fredag", "Udgivelse     Team         28. okt."], fontSize: 20)
    ]),
    LanguageSpec(tag: "nl-NL", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Projectbibliotheek", "Notities zoeken", "Recente opnamen", "Map openen", "Zojuist opgeslagen"], fontSize: 22),
        Sample(category: "code", lines: ["// Bewaar de nieuwste opname", "struct CaptureRecord {", "    let titel: String", "    func opslaan() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Een duidelijker beeld van het werk", "Leg nuttige details vast zolang ze vers zijn.", "Kleine observaties verbinden ideeën.", "Bekijk deze notities voor de volgende sessie."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "De nieuwe stroom is klaar voor controle.", "Jon  09:46", "Ik test die na de ontwerpcontrole."], fontSize: 21),
        Sample(category: "table", lines: ["Taak          Eigenaar      Deadline", "OCR-controle  Mira          Vandaag", "CI-runner     Jon           Vrijdag", "Release       Team          28 okt."], fontSize: 20)
    ]),
    LanguageSpec(tag: "no-NO", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Prosjektbibliotek", "Søk i notater", "Nylige opptak", "Åpne mappe", "Lagret nå"], fontSize: 22),
        Sample(category: "code", lines: ["// Behold det nyeste opptaket", "struct CaptureRecord {", "    let tittel: String", "    func lagre() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Et tydeligere bilde av arbeidet", "Lagre nyttige detaljer mens de er ferske.", "Små observasjoner knytter ideer sammen.", "Se gjennom notatene før neste økt."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Den nye flyten er klar for gjennomgang.", "Jon  09:46", "Jeg tester den etter designsjekken."], fontSize: 21),
        Sample(category: "table", lines: ["Oppgave       Ansvarlig     Frist", "OCR-kontroll  Mira          I dag", "CI-runner     Jon           Fredag", "Utgivelse     Team          28. okt."], fontSize: 20)
    ]),
    LanguageSpec(tag: "nn-NO", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Prosjektbibliotek", "Søk i notat", "Nylege opptak", "Opne mappe", "Lagra no"], fontSize: 22),
        Sample(category: "code", lines: ["// Ta vare på siste opptak", "struct CaptureRecord {", "    let tittel: String", "    func lagre() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Eit tydelegare bilete av arbeidet", "Lagre nyttige detaljar medan dei er ferske.", "Små observasjonar knyter idear saman.", "Sjå gjennom notata før neste økt."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Den nye flyten er klar for gjennomgang.", "Jon  09:46", "Eg testar han etter designsjekken."], fontSize: 21),
        Sample(category: "table", lines: ["Oppgåve       Ansvarleg     Frist", "OCR-kontroll  Mira          I dag", "CI-runner     Jon           Fredag", "Utgjeving     Team          28. okt."], fontSize: 20)
    ]),
    LanguageSpec(tag: "nb-NO", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Prosjektbibliotek", "Søk i notater", "Nylige opptak", "Åpne mappe", "Lagret nå"], fontSize: 22),
        Sample(category: "code", lines: ["// Behold det nyeste opptaket", "struct CaptureRecord {", "    let tittel: String", "    func lagre() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Et tydeligere bilde av arbeidet", "Lagre nyttige detaljer mens de er ferske.", "Små observasjoner knytter ideer sammen.", "Se gjennom notatene før neste økt."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Den nye flyten er klar for gjennomgang.", "Jon  09:46", "Jeg tester den etter designsjekken."], fontSize: 21),
        Sample(category: "table", lines: ["Oppgave       Ansvarlig     Frist", "OCR-kontroll  Mira          I dag", "CI-runner     Jon           Fredag", "Utgivelse     Team          28. okt."], fontSize: 20)
    ]),
    LanguageSpec(tag: "ms-MY", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Pustaka projek", "Cari nota", "Rakaman terkini", "Buka folder", "Disimpan sebentar tadi"], fontSize: 21),
        Sample(category: "code", lines: ["// Simpan rakaman terkini", "struct CaptureRecord {", "    let tajuk: String", "    func simpan() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Pandangan kerja yang lebih jelas", "Catat butiran berguna semasa masih baharu.", "Pemerhatian kecil menghubungkan idea.", "Semak nota ini sebelum sesi seterusnya."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Aliran baharu sedia untuk disemak.", "Jon  09:46", "Saya akan mengujinya selepas semakan reka bentuk."], fontSize: 20),
        Sample(category: "table", lines: ["Tugas         Pemilik       Tarikh akhir", "Semakan OCR   Mira          Hari ini", "Runner CI     Jon           Jumaat", "Keluaran      Pasukan       28 Okt."], fontSize: 18)
    ]),
    LanguageSpec(tag: "pl-PL", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Biblioteka projektów", "Szukaj notatek", "Ostatnie przechwycenia", "Otwórz folder", "Zapisano przed chwilą"], fontSize: 21),
        Sample(category: "code", lines: ["// Zachowaj najnowszy zapis", "struct CaptureRecord {", "    let tytul: String", "    func zapisz() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Wyraźniejszy obraz pracy", "Zapisuj przydatne szczegóły, póki są świeże.", "Małe obserwacje łączą odległe pomysły.", "Przejrzyj notatki przed następną sesją."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Nowy przepływ jest gotowy do sprawdzenia.", "Jon  09:46", "Przetestuję go po przeglądzie projektu."], fontSize: 21),
        Sample(category: "table", lines: ["Zadanie       Osoba        Termin", "Przegląd OCR  Mira          Dzisiaj", "Runner CI     Jon           Piątek", "Wydanie       Zespół        28 paź."], fontSize: 19)
    ]),
    LanguageSpec(tag: "ro-RO", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Biblioteca de proiecte", "Caută în notițe", "Capturi recente", "Deschide dosarul", "Salvat chiar acum"], fontSize: 21),
        Sample(category: "code", lines: ["// Păstrează captura recentă", "struct CaptureRecord {", "    let titlu: String", "    func salveaza() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["O perspectivă mai clară asupra muncii", "Notează detaliile utile cât sunt proaspete.", "Observațiile mici conectează idei îndepărtate.", "Revizuiește notițele înaintea sesiunii următoare."], fontSize: 19),
        Sample(category: "chat", lines: ["Mira  09:42", "Fluxul nou este gata pentru revizuire.", "Jon  09:46", "Îl testez după verificarea designului."], fontSize: 21),
        Sample(category: "table", lines: ["Sarcină       Responsabil  Termen", "Revizuire OCR Mira         Astăzi", "Runner CI     Jon          Vineri", "Lansare       Echipa       28 oct."], fontSize: 20)
    ]),
    LanguageSpec(tag: "sv-SE", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Projektbibliotek", "Sök bland anteckningar", "Senaste fångster", "Öppna mapp", "Sparades nyss"], fontSize: 21),
        Sample(category: "code", lines: ["// Behåll den senaste fångsten", "struct CaptureRecord {", "    let titel: String", "    func spara() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["En tydligare bild av arbetet", "Spara användbara detaljer medan de är färska.", "Små observationer kopplar samman idéer.", "Gå igenom anteckningarna före nästa session."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Det nya flödet är klart för granskning.", "Jon  09:46", "Jag testar det efter designkontrollen."], fontSize: 21),
        Sample(category: "table", lines: ["Uppgift       Ansvarig     Tidsfrist", "OCR-granskning Mira        I dag", "CI-runner     Jon          Fredag", "Utgåva        Team         28 okt."], fontSize: 19)
    ]),
    LanguageSpec(tag: "fi-FI", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Projektikirjasto", "Hae muistiinpanoista", "Viimeisimmät tallenteet", "Avaa kansio", "Tallennettu juuri"], fontSize: 21),
        Sample(category: "code", lines: ["// Säilytä uusin tallenne", "struct CaptureRecord {", "    let otsikko: String", "    func tallenna() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Selkeämpi näkymä työhön", "Kirjaa hyödylliset tiedot niiden ollessa tuoreita.", "Pienet havainnot yhdistävät etäisiä ideoita.", "Lue muistiinpanot ennen seuraavaa istuntoa."], fontSize: 20),
        Sample(category: "chat", lines: ["Mira  09:42", "Uusi työnkulku on valmis tarkistettavaksi.", "Jon  09:46", "Testaan sitä suunnittelutarkistuksen jälkeen."], fontSize: 20),
        Sample(category: "table", lines: ["Tehtävä      Vastuuhenkilö  Määräaika", "OCR-tarkistus Mira          Tänään", "CI-runner    Jon            Perjantai", "Julkaisu     Tiimi          28. lokak."], fontSize: 18)
    ]),
    LanguageSpec(tag: "zh-Hans", font: "PingFang SC", samples: [
        Sample(category: "ui", lines: ["项目资料库", "搜索笔记", "最近捕获", "打开文件夹", "刚刚已保存"], fontSize: 24),
        Sample(category: "ui", lines: ["快速笔记", "添加标题", "开始会话", "取消     保存笔记", "更改已同步"], fontSize: 24),
        Sample(category: "code", lines: ["// 保留最近的记录", "struct CaptureRecord {", "    let 标题: String", "    func 保存() { writeVault() }", "}"], fontSize: 20),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let 最近记录 = loadRecords()", "    return 最近记录.sorted()", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["更清晰地查看工作", "趁细节还清楚时记录有用的信息。", "小小的观察也能连接不同的想法。", "下次会话前请查看这些笔记。"], fontSize: 23),
        Sample(category: "docs", lines: ["项目笔记", "为每个新想法写一个简短标题。", "把相关决定放在同一部分。", "更新于 2026 年 10 月 19 日"], fontSize: 23),
        Sample(category: "chat", lines: ["米拉  09:42", "新的捕获流程已经可以开始评审。", "乔恩  09:46", "我会在设计检查后进行测试。"], fontSize: 23),
        Sample(category: "chat", lines: ["团队频道  #计划", "米拉：请保持第一个屏幕简洁。", "乔恩：表格现在包含来源链接。", "2 条回复     添加表情"], fontSize: 22),
        Sample(category: "table", lines: ["项目        数量        状态", "草稿        12          就绪", "图片        4           待审", "导出        2           完成"], fontSize: 23),
        Sample(category: "table", lines: ["任务        负责人      截止时间", "OCR 评审    米拉        今天", "CI 运行器   乔恩        周五", "发布        团队        10 月 28 日"], fontSize: 22)
    ]),
    LanguageSpec(tag: "zh-Hant", font: "PingFang TC", samples: [
        Sample(category: "ui", lines: ["專案資料庫", "搜尋筆記", "最近擷取", "開啟資料夾", "剛剛已儲存"], fontSize: 24),
        Sample(category: "ui", lines: ["快速筆記", "新增標題", "開始工作階段", "取消     儲存筆記", "變更已同步"], fontSize: 24),
        Sample(category: "code", lines: ["// 保留最近的記錄", "struct CaptureRecord {", "    let 標題: String", "    func 儲存() { writeVault() }", "}"], fontSize: 20),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let 最近記錄 = loadRecords()", "    return 最近記錄.sorted()", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["更清楚地查看工作", "趁細節還清楚時記下有用資訊。", "小小的觀察也能連結不同想法。", "下次工作階段前請查看這些筆記。"], fontSize: 23),
        Sample(category: "docs", lines: ["專案筆記", "為每個新想法寫一個簡短標題。", "把相關決策放在同一個區段。", "更新於 2026 年 10 月 19 日"], fontSize: 23),
        Sample(category: "chat", lines: ["米拉  09:42", "新的擷取流程已經可以開始檢視。", "喬恩  09:46", "我會在設計檢查後進行測試。"], fontSize: 23),
        Sample(category: "chat", lines: ["團隊頻道  #規劃", "米拉：請讓第一個畫面保持簡潔。", "喬恩：表格現在包含來源連結。", "2 則回覆     新增表情"], fontSize: 22),
        Sample(category: "table", lines: ["項目        數量        狀態", "草稿        12          就緒", "圖片        4           待審", "匯出        2           完成"], fontSize: 23),
        Sample(category: "table", lines: ["任務        負責人      截止日期", "OCR 檢視    米拉        今天", "CI 執行器   喬恩        星期五", "發布        團隊        10 月 28 日"], fontSize: 22)
    ]),
    LanguageSpec(tag: "ja-JP", font: "Hiragino Sans", samples: [
        Sample(category: "ui", lines: ["プロジェクトライブラリ", "ノートを検索", "最近のキャプチャ", "フォルダを開く", "たった今保存しました"], fontSize: 21),
        Sample(category: "ui", lines: ["クイックノート", "見出しを追加", "セッションを開始", "キャンセル     保存", "変更を同期しました"], fontSize: 22),
        Sample(category: "code", lines: ["// 最新の記録を保持", "struct CaptureRecord {", "    let タイトル: String", "    func 保存() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "code", lines: ["func collectRecords() -> [CaptureRecord] {", "    let 最近の記録 = loadRecords()", "    return 最近の記録.sorted()", "}"], fontSize: 18),
        Sample(category: "docs", lines: ["作業をより明確に見る", "役立つ詳細は新しいうちに記録します。", "小さな気づきが離れたアイデアをつなぎます。", "次のセッションの前にノートを確認します。"], fontSize: 20),
        Sample(category: "docs", lines: ["プロジェクトノート", "新しいアイデアには短いタイトルを付けます。", "関連する決定は同じセクションにまとめます。", "2026年10月19日に更新"], fontSize: 20),
        Sample(category: "chat", lines: ["ミラ  09:42", "新しいキャプチャ手順のレビューができます。", "ジョン  09:46", "デザイン確認のあとでテストします。"], fontSize: 20),
        Sample(category: "chat", lines: ["チームチャンネル  #計画", "ミラ：最初の画面はシンプルにしましょう。", "ジョン：表にソースリンクを追加しました。", "返信 2 件     リアクションを追加"], fontSize: 19),
        Sample(category: "table", lines: ["項目        件数        状態", "下書き      12          準備完了", "画像        4           確認中", "書き出し    2           完了"], fontSize: 20),
        Sample(category: "table", lines: ["タスク      担当者      期限", "OCR レビュー ミラ       今日", "CI ランナー ジョン      金曜日", "リリース    チーム      10月28日"], fontSize: 20)
    ]),
    LanguageSpec(tag: "ko-KR", font: "Apple SD Gothic Neo", samples: [
        Sample(category: "ui", lines: ["프로젝트 라이브러리", "노트 검색", "최근 캡처", "폴더 열기", "방금 저장됨"], fontSize: 22),
        Sample(category: "code", lines: ["// 최신 캡처를 보관합니다", "struct CaptureRecord {", "    let 제목: String", "    func 저장() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["작업을 더 명확하게 보기", "유용한 세부 정보를 기록해 두세요.", "작은 관찰이 서로 다른 생각을 이어 줍니다.", "다음 세션 전에 이 노트를 확인하세요."], fontSize: 20),
        Sample(category: "chat", lines: ["미라  09:42", "새 캡처 흐름을 검토할 준비가 됐어요.", "존  09:46", "디자인 확인 후에 테스트할게요."], fontSize: 21),
        Sample(category: "table", lines: ["작업          담당자      기한", "OCR 검토     미라        오늘", "CI 러너      존          금요일", "릴리스       팀          10월 28일"], fontSize: 20)
    ]),
    LanguageSpec(tag: "ru-RU", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Библиотека проектов", "Поиск по заметкам", "Недавние снимки", "Открыть папку", "Сохранено сейчас"], fontSize: 21),
        Sample(category: "code", lines: ["// Сохранить последнюю запись", "struct CaptureRecord {", "    let название: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Работа видна яснее", "Записывайте полезные детали, пока они свежи.", "Небольшие наблюдения связывают разные идеи.", "Просмотрите заметки перед следующей сессией."], fontSize: 20),
        Sample(category: "chat", lines: ["Мира  09:42", "Новый процесс готов к проверке.", "Джон  09:46", "Проверю его после просмотра дизайна."], fontSize: 21),
        Sample(category: "table", lines: ["Задача        Владелец     Срок", "Проверка OCR  Мира         Сегодня", "CI runner     Джон         Пятница", "Релиз         Команда      28 окт."], fontSize: 20)
    ]),
    LanguageSpec(tag: "uk-UA", font: "Helvetica Neue", samples: [
        Sample(category: "ui", lines: ["Бібліотека проєктів", "Пошук у нотатках", "Останні знімки", "Відкрити теку", "Збережено щойно"], fontSize: 21),
        Sample(category: "code", lines: ["// Зберегти останній запис", "struct CaptureRecord {", "    let назва: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["Робота стає зрозумілішою", "Записуйте корисні деталі, поки вони свіжі.", "Невеликі спостереження поєднують різні ідеї.", "Перегляньте нотатки перед наступною сесією."], fontSize: 20),
        Sample(category: "chat", lines: ["Міра  09:42", "Новий процес готовий до перевірки.", "Джон  09:46", "Перевірю його після перегляду дизайну."], fontSize: 21),
        Sample(category: "table", lines: ["Завдання      Відповідальний  Термін", "Перевірка OCR Міра            Сьогодні", "CI runner     Джон            П’ятниця", "Реліз         Команда         28 жовт."], fontSize: 19)
    ]),
    LanguageSpec(tag: "th-TH", font: "Thonburi", samples: [
        Sample(category: "ui", lines: ["คลังโครงการ", "ค้นหาบันทึก", "รายการล่าสุด", "เปิดโฟลเดอร์", "บันทึกเมื่อสักครู่"], fontSize: 22),
        Sample(category: "code", lines: ["// เก็บรายการล่าสุดไว้", "struct CaptureRecord {", "    let ชื่อ: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["มองเห็นงานได้ชัดเจนขึ้น", "จดรายละเอียดที่เป็นประโยชน์ขณะที่ยังจำได้", "ข้อสังเกตเล็กน้อยช่วยเชื่อมโยงแนวคิด", "ทบทวนบันทึกก่อนเริ่มเซสชันถัดไป"], fontSize: 21),
        Sample(category: "chat", lines: ["มีรา  09:42", "ขั้นตอนใหม่พร้อมให้ตรวจสอบแล้ว", "จอน  09:46", "ฉันจะทดสอบหลังตรวจแบบเสร็จ"], fontSize: 21),
        Sample(category: "table", lines: ["งาน            ผู้รับผิดชอบ  กำหนดส่ง", "ตรวจ OCR       มีรา          วันนี้", "CI runner      จอน           วันศุกร์", "เผยแพร่        ทีม            28 ต.ค."], fontSize: 19)
    ]),
    LanguageSpec(tag: "ar-SA", font: "Geeza Pro", samples: [
        Sample(category: "ui", lines: ["مكتبة المشاريع", "ابحث في الملاحظات", "اللقطات الأخيرة", "افتح المجلد", "حُفظ الآن"], fontSize: 22),
        Sample(category: "code", lines: ["// احتفظ بأحدث لقطة", "struct CaptureRecord {", "    let title: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["رؤية أوضح للعمل", "دوّن التفاصيل المفيدة ما دامت حديثة.", "الملاحظات الصغيرة تربط بين الأفكار.", "راجع هذه الملاحظات قبل الجلسة التالية."], fontSize: 20),
        Sample(category: "chat", lines: ["ميرا  09:42", "أصبح المسار الجديد جاهزًا للمراجعة.", "جون  09:46", "سأختبره بعد مراجعة التصميم."], fontSize: 21),
        Sample(category: "table", lines: ["المهمة        المسؤول      الموعد", "مراجعة OCR    ميرا          اليوم", "مشغل CI       جون           الجمعة", "الإصدار       الفريق        28 أكتوبر"], fontSize: 19)
    ]),
    LanguageSpec(tag: "ars-SA", font: "Geeza Pro", samples: [
        Sample(category: "ui", lines: ["مكتبة المشاريع", "ابحث عن الملاحظات", "آخر اللقطات", "افتح المجلد", "تم الحفظ الآن"], fontSize: 22),
        Sample(category: "code", lines: ["// خلك محتفظ بآخر لقطة", "struct CaptureRecord {", "    let title: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["شوف الشغل بصورة أوضح", "سجل التفاصيل المفيدة وهي توها جديدة.", "الملاحظات الصغيرة تربط الأفكار ببعض.", "راجع هالملاحظات قبل الجلسة الجاية."], fontSize: 20),
        Sample(category: "chat", lines: ["ميرا  09:42", "المسار الجديد صار جاهز للمراجعة.", "جون  09:46", "بجربه بعد ما أراجع التصميم."], fontSize: 21),
        Sample(category: "table", lines: ["المهمة        المسؤول      الموعد", "مراجعة OCR    ميرا          اليوم", "مشغل CI       جون           الجمعة", "الإصدار       الفريق        28 أكتوبر"], fontSize: 19)
    ]),
    LanguageSpec(tag: "hi-IN", font: "Kohinoor Devanagari", samples: [
        Sample(category: "ui", lines: ["प्रोजेक्ट लाइब्रेरी", "नोट खोजें", "हाल के कैप्चर", "फ़ोल्डर खोलें", "अभी सहेजा गया"], fontSize: 22),
        Sample(category: "code", lines: ["// सबसे नया कैप्चर रखें", "struct CaptureRecord {", "    let शीर्षक: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["काम को और साफ़ देखें", "उपयोगी जानकारी ताज़ा रहते लिखें।", "छोटी बातें दूर के विचार जोड़ती हैं।", "अगले सत्र से पहले ये नोट देखें।"], fontSize: 21),
        Sample(category: "chat", lines: ["मीरा  09:42", "नया कैप्चर तरीका समीक्षा के लिए तैयार है।", "जॉन  09:46", "डिज़ाइन जाँच के बाद मैं इसे परखूँगा।"], fontSize: 20),
        Sample(category: "table", lines: ["काम           ज़िम्मेदार    समय सीमा", "OCR समीक्षा   मीरा          आज", "CI runner     जॉन           शुक्रवार", "रिलीज़        टीम           28 अक्तू."], fontSize: 19)
    ]),
    LanguageSpec(tag: "mr-IN", font: "Kohinoor Devanagari", samples: [
        Sample(category: "ui", lines: ["प्रकल्प लायब्ररी", "नोंदी शोधा", "अलीकडील जतन", "फोल्डर उघडा", "आत्ताच जतन केले"], fontSize: 22),
        Sample(category: "code", lines: ["// नवीन नोंद जतन करा", "struct CaptureRecord {", "    let शीर्षक: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["काम अधिक स्पष्टपणे पाहा", "उपयुक्त तपशील ताजे असतानाच लिहा.", "लहान निरीक्षणे दूरच्या कल्पना जोडतात.", "पुढील सत्राआधी या नोंदी वाचा."], fontSize: 21),
        Sample(category: "chat", lines: ["मीरा  09:42", "नवीन कॅप्चर पद्धत तपासण्यासाठी तयार आहे.", "जॉन  09:46", "रचना तपासल्यानंतर मी चाचणी करेन."], fontSize: 20),
        Sample(category: "table", lines: ["काम            जबाबदार     अंतिम तारीख", "OCR तपासणी    मीरा          आज", "CI runner      जॉन           शुक्रवार", "प्रकाशन        टीम           २८ ऑक्टो."], fontSize: 19)
    ]),
    LanguageSpec(tag: "yue-Hans", font: "PingFang SC", samples: [
        Sample(category: "ui", lines: ["项目资料库", "搜寻笔记", "最近嘅记录", "打开文件夹", "啱啱已保存"], fontSize: 23),
        Sample(category: "code", lines: ["// 留低最新嘅记录", "struct CaptureRecord {", "    let 标题: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["清楚咁睇工作进度", "趁啲细节仲记得就写低。", "细微观察都可以连起唔同想法。", "下次开会之前睇吓呢啲笔记。"], fontSize: 21),
        Sample(category: "chat", lines: ["米拉  09:42", "新嘅记录流程已经可以开始睇喇。", "乔恩  09:46", "我检查完设计就会试吓。"], fontSize: 21),
        Sample(category: "table", lines: ["项目        数量        状态", "草稿        12          就绪", "图片        4           待审", "导出        2           完成"], fontSize: 22)
    ]),
    LanguageSpec(tag: "yue-Hant", font: "PingFang TC", samples: [
        Sample(category: "ui", lines: ["專案資料庫", "搜尋筆記", "最近嘅記錄", "開啟資料夾", "啱啱已儲存"], fontSize: 23),
        Sample(category: "code", lines: ["// 留低最新嘅記錄", "struct CaptureRecord {", "    let 標題: String", "    func save() { writeVault() }", "}"], fontSize: 19),
        Sample(category: "docs", lines: ["清楚咁睇工作進度", "趁啲細節仲記得就寫低。", "細微觀察都可以連起唔同想法。", "下次開會之前睇吓呢啲筆記。"], fontSize: 21),
        Sample(category: "chat", lines: ["米拉  09:42", "新嘅記錄流程已經可以開始睇喇。", "喬恩  09:46", "我檢查完設計就會試吓。"], fontSize: 21),
        Sample(category: "table", lines: ["項目        數量        狀態", "草稿        12          就緒", "圖片        4           待審", "匯出        2           完成"], fontSize: 22)
    ])
]

func pngData(for image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "Corpus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "Corpus", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not finalize PNG"])
    }
    return data as Data
}

func cgColor(_ color: NSColor) -> CGColor {
    color.usingColorSpace(.deviceRGB)!.cgColor
}

func render(_ sample: Sample, language: LanguageSpec, scale: Double, dark: Bool) throws -> CGImage {
    let logicalWidth = 960
    let logicalHeight = 540
    let pixelWidth = Int(Double(logicalWidth) * scale)
    let pixelHeight = Int(Double(logicalHeight) * scale)
    guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "Corpus", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create canvas"])
    }
    context.scaleBy(x: scale, y: scale)
    let width = CGFloat(logicalWidth)
    let height = CGFloat(logicalHeight)
    context.setFillColor(cgColor(dark ? NSColor(calibratedWhite: 0.105, alpha: 1) : .white))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let foreground = cgColor(dark ? NSColor(calibratedWhite: 0.93, alpha: 1) : NSColor(calibratedWhite: 0.1, alpha: 1))
    let muted = cgColor(dark ? NSColor(calibratedWhite: 0.67, alpha: 1) : NSColor(calibratedWhite: 0.38, alpha: 1))
    context.setFillColor(cgColor(dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)))
    context.fill(CGRect(x: 32, y: 32, width: width - 64, height: height - 64))

    let category = sample.category
    let bodyFamily = category == "code" ? "Menlo" : language.font
    let bodySize = sample.fontSize
    let lineStep: CGFloat = category == "table" ? 54 : 49
    var top: CGFloat = 98
    for (index, string) in sample.lines.enumerated() {
        let size = bodySize
        let baseFont = CTFontCreateWithName(bodyFamily as CFString, size, nil)
        let fullRange = CFRange(location: 0, length: (string as NSString).length)
        let font = CTFontCreateForString(baseFont, string as CFString, fullRange)
        let color = (category == "chat" && index % 2 == 0) || (category == "table" && index == 0) ? foreground : muted
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 62, y: height - top - size)
        CTLineDraw(line, context)
        top += lineStep
    }
    guard let image = context.makeImage() else {
        throw NSError(domain: "Corpus", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not render image"])
    }
    return image
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "Corpus", code: 5, userInfo: [NSLocalizedDescriptionKey: "Usage: swift conformance/ocr/generate-corpus.swift <outdir>"])
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    if FileManager.default.fileExists(atPath: output.path) {
        try FileManager.default.removeItem(at: output)
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var entries: [CorpusEntry] = []
    let scales = [1.0, 1.5, 2.0]
    for language in languageSpecs {
        for (index, sample) in language.samples.enumerated() {
            let scale = scales[(index + language.tag.utf8.count) % scales.count]
            let dark = (index + language.tag.utf8.count).isMultiple(of: 2)
            let suffix = dark ? "dark" : "light"
            let filename = String(format: "%@/%@-%02d@%.1f-%@.png", language.tag, sample.category, index % 2 + 1, scale, suffix)
            let fileURL = output.appendingPathComponent(filename)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let image = try render(sample, language: language, scale: scale, dark: dark)
            try pngData(for: image).write(to: fileURL, options: .atomic)
            entries.append(CorpusEntry(file: filename, category: sample.category, language: language.tag,
                                       scale: scale, dark: dark, groundTruth: sample.lines.joined(separator: "\n")))
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let manifest = try encoder.encode(entries)
    try manifest.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
    print("Generated \(entries.count) OCR samples in \(output.path)")
} catch {
    FileHandle.standardError.write(Data("Corpus generation failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
