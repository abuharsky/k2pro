# Публикация K2 Pro — автоматизация и ключи

Цель: тег в git → подписанная сборка на TestFlight, без ручной работы.
Выход в публичный App Store остаётся отдельным осознанным шагом.

Пайплайн: [`.github/workflows/ios-testflight.yml`](../.github/workflows/ios-testflight.yml) ·
конфиг fastlane: [`app/ios/fastlane/`](../app/ios/fastlane/).

---

## Модель безопасности

Репозиторий публичный, поэтому **в дереве нет ни одного секрета**. Всё
чувствительное живёт в GitHub Actions Secrets и попадает в сборку через
переменные окружения. Три независимых доступа, каждый с минимальным радиусом
поражения при утечке:

| Доступ | Что им можно | Что нельзя (даже при утечке) |
|---|---|---|
| **App Store Connect API — individual key** (роль App Manager, доступ только к k2pro) | Заливать билды и метаданные **только k2pro** | Другие приложения; финансы и продажи; **provisioning** — Apple запрещает individual-ключам трогать сертификаты и профили |
| **match, read-only** (deploy-доступ к приватному репо + `MATCH_PASSWORD`) | Прочитать и расшифровать один distribution-сертификат | Что-либо записать; создать/отозвать сертификат; без `MATCH_PASSWORD` содержимое бесполезно |
| **Google Play service account** (если добавим Android) | Релиз **только этого** приложения | Другие приложения; консольные настройки вне выданных прав |

Почему это устойчиво к утечке:

- **Ключ ≠ ключ от королевства.** Team-key даёт доступ ко всей команде — мы им
  не пользуемся. Individual-key наследует права одного пользователя-сервисника,
  которому выдан ровно один app.
- **CI никогда не создаёт сертификаты.** `Matchfile` включает `readonly` на CI,
  а lane `certificates` прямо отказывается работать при `CI=true`. Перевыпуск
  подписи — только руками, локально.
- **Тесты — гейт.** `fastlane beta` не зальёт сборку, если `flutter test` упал.
- **Прод — за отдельной кнопкой.** Lane `release` требует `RELEASE=confirm` и
  не висит в автоматическом workflow.

---

## Одноразовая настройка (только вы — за Apple 2FA)

Эти шаги я выполнить не могу: нужен ваш вход в Apple с двухфакторкой.

### 1. Запись приложения в App Store Connect
App Store Connect → Apps → **+** → New App. Bundle ID `ru.bukharskiy.k2pro`
(должен быть заранее зарегистрирован в Developer portal с watch-расширением
`ru.bukharskiy.k2pro.watchkitapp`). Название — см. раздел «Имя и ревью» ниже.

### 2. Пользователь-сервисник с доступом только к k2pro
Users and Access → **+** → заведите отдельного пользователя (например
`ci@ваш-домен`), роль **App Manager**, и в «Apps» снимите «All Apps», оставив
только **K2 Pro**. Это и есть ограничение радиуса: ключ этого пользователя не
увидит ничего другого.

### 3. Individual API key
Войдите в App Store Connect **под этим сервисником** → имя в правом верхнем углу
→ Edit Profile → **Individual API Key** → Generate. Скачайте `.p8` (даётся
один раз). Запишите **Key ID** и **Issuer ID**.

### 4. Приватный репозиторий для подписи
Создайте **приватный** репозиторий, например `k2pro-signing`. В нём match будет
хранить зашифрованные сертификат и профили. Он **не** должен быть публичным и
**не** связан с этим репо.

### 5. Локально сгенерировать подпись (один раз)
```bash
cd app/ios
bundle install
export MATCH_GIT_URL="git@github.com:abuharsky/k2pro-signing.git"
export MATCH_PASSWORD="<придумайте-длинный-пароль-шифрования>"
export ASC_KEY_ID="<Key ID>" ASC_ISSUER_ID="<Issuer ID>"
export ASC_KEY_P8="$(cat /путь/к/AuthKey_XXXX.p8)"
bundle exec fastlane certificates      # создаст cert + профили в signing-репо
```
Сохраните `MATCH_PASSWORD` в менеджере паролей — без него подпись не
расшифровать.

### 6. Read-only доступ CI к signing-репо
Fine-grained Personal Access Token, привязанный **только** к `k2pro-signing`,
права **Contents: Read-only**. Затем:
```bash
printf 'x-access-token:<PAT>' | base64      # → значение MATCH_GIT_BASIC_AUTHORIZATION
```
(В `Matchfile` для CI используйте https-URL signing-репо: положите его в
`MATCH_GIT_URL` секретом.)

### 7. Секреты в GitHub
Settings → Secrets and variables → Actions → New repository secret:

| Секрет | Откуда |
|---|---|
| `ASC_KEY_ID` | шаг 3 |
| `ASC_ISSUER_ID` | шаг 3 |
| `ASC_KEY_P8` | `base64 -i AuthKey_XXXX.p8` (workflow ждёт base64) |
| `MATCH_GIT_URL` | https-URL signing-репо |
| `MATCH_PASSWORD` | шаг 5 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | шаг 6 |
| `ITC_TEAM_ID` | если у вас несколько ASC-команд (иначе можно опустить) |

---

## Как выпускать

TestFlight — автоматически по тегу:
```bash
git tag v1.0.0+1
git push origin v1.0.0+1
```
Workflow соберёт, подпишет и зальёт в TestFlight. В публичный ревью ничего не
уходит.

Промоушен в App Store — осознанно, локально:
```bash
cd app/ios
RELEASE=confirm bundle exec fastlane release
```
`automatic_release: false` — даже после прохождения ревью финальную кнопку
«Release» вы жмёте сами в App Store Connect.

---

## Ротация и отзыв

- **Скомпрометирован ASC-ключ:** App Store Connect → под сервисником → Revoke
  Individual API Key, сгенерировать новый, обновить три секрета. Прод и другие
  приложения не затронуты — ключ и так их не видел.
- **Скомпрометирован `MATCH_PASSWORD` или PAT:** `fastlane match nuke` локально,
  перевыпустить подпись (шаг 5), сменить PAT и пароль. Публичный репо чист по
  определению — ротация не касается кода.

---

## Имя и ревью (важно)

Приложение — **неофициальный** клиент к чужому железу (Cera+ iKape K2 Pro;
официальное приложение — «Happygo Cera»). Публикация под именем «K2 Pro»
несёт риск отклонения на ревью (Guideline 4.1/5.2 — чужой товарный знак) и
претензий от вендора. Рекомендуется нейтральное имя и честное «unofficial
companion» в описании. Пайплайн от имени не зависит — переименование меняет
только `CFBundleDisplayName` и метаданные, не подпись.

TestFlight (internal) публичного ревью не проходит — можно поднять пайплайн и
раздать бету, а вопрос имени решить перед первым публичным сабмитом.

---

## Android / Google Play

Android-таргета в проекте пока нет (`flutter create --platforms=android`,
BLE-разрешения, отдельная подпись). Часы останутся iOS-only. Когда дойдут руки —
добавляется отдельный `Fastfile` с lane `upload_to_play_store` и
service-account по той же логике минимального доступа.
