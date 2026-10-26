# CLAUDE.md — Mission Control (Gleam on BEAM)

Цей файл — головна інструкція для Claude Code в цьому репозиторії. Читай його перед кожною задачею і оновлюй секцію **Status** після кожного етапу.

---

## 1. Що ми будуємо

**Mission Control** — живий дашборд «бортового комп'ютера космічного корабля», що працює на BEAM.

- Підсистеми корабля (Reactor, Shields, Navigation, Comms, LifeSupport) — це **OTP-актори під супервізором**. Кожна має свій стан: потужність, навантаження, температуру, статус.
- UI у стилі sci-fi HUD (натхнення — проєкт Arwes) у реальному часі показує стан підсистем, метрики самої Erlang VM і журнал подій.
- Головна демонстрація: користувач натискає **INJECT FAULT**, підсистема падає, панель спалахує червоним, супервізор перезапускає актор, і статус повертається в `NOMINAL`. Так стає видно, як працює відмовостійкість OTP.

Мета проєкту — навчальна й демонстраційна: показати сильні сторони Gleam (типи, спільний код між Erlang і JS, OTP) у гарній обгортці.

---

## 2. Жорсткі правила (не порушувати)

1. **Весь код на Gleam.** Без Gleam дозволено лише:
   - один файл стилів `styles.css` і HTML-оболонку `index.html`;
   - `Dockerfile`, `docker-compose.yml`, `justfile`, `gleam.toml`, `manifest.toml`, `.dockerignore`, `README.md`;
   - шрифти та статичні зображення у `priv/static/`.
2. **FFI — тільки в крайньому разі.** Спершу шукай готовий Gleam-пакет. Далі використовуй `@external` на вже наявні функції Erlang/OTP чи браузера (наприклад, `erlang:system_info/1`). Окремий `.erl`/`.mjs` файл можна додати, лише якщо інакше неможливо: до 30 рядків і з коментарем, чому це потрібно.
3. **Arwes не підключати.** Жодних пакетів `@arwes/*`, жодного копіювання їхнього коду, SVG, звуків, шрифтів чи текстів. Ми лише відтворюємо *ідеї* (рамки, що малюються лініями, текст, який «розшифровується», оркестрація анімацій через стани) власною реалізацією на Gleam.
4. **Жодних JS-фреймворків.** Не використовуй React, Vue, Tailwind чи npm-залежності в коді проєкту. Клієнт — Lustre, а збирання — штатним інструментом Lustre (`lustre_dev_tools`).
5. **Єдиний спосіб запуску — `docker compose up --build`.** На хості потрібен лише Docker, локальний `gleam` — необов'язковий.
6. **Не вигадуй API.** Lustre, mist і gleam_otp змінювали API між мажорними версіями. Перед використанням функції звір її з hexdocs встановленої версії або з кодом у `build/packages/`.
7. **Мова.** Код, ідентифікатори, коментарі та коміти — англійською. Тексти UI — англійською, у стилі sci-fi (`SUBSYSTEM FAILURE`, `REROUTING POWER`…).

---

## 3. Стек

| Шар | Технології |
|---|---|
| Мова | Gleam (остання стабільна 1.x, версію зафіксувати в Dockerfile) |
| Сервер (target `erlang`) | `mist` (HTTP + WebSocket), `gleam_otp` (актори, супервізор), `gleam_erlang`, `gleam_http`, `gleam_json` |
| Клієнт (target `javascript`) | `lustre` (SPA, Elm-архітектура), `lustre_dev_tools` (dev-залежність, збирання), за потреби `lustre_websocket` або `plinth` (браузерні API) |
| Спільне (`shared`) | чистий Gleam без target-специфічного коду: типи протоколу і JSON-кодеки |
| Тести | `gleeunit` у кожному пакеті |

Будь-яку залежність поза цим списком додавай лише з обґрунтуванням у коміті.

**Чому SPA, а не Lustre server components:** анімації (малювання рамок, розшифровування тексту) мають працювати на клієнті з частотою 60 fps. Server components вимагали б обміну даними з сервером на кожен кадр. Тому сервер лише стримить доменні події, а вся анімація живе на клієнті.

---

## 4. Структура репозиторію

```
mission_control/
├── CLAUDE.md
├── README.md
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── shared/                      # target-agnostic
│   ├── gleam.toml
│   ├── src/shared/
│   │   ├── protocol.gleam       # типи подій і команд
│   │   └── codec.gleam          # JSON encode/decode
│   └── test/
├── server/                      # target = "erlang"
│   ├── gleam.toml               # shared = { path = "../shared" }
│   ├── src/
│   │   ├── server.gleam         # main: старт супервізора + mist
│   │   └── server/
│   │       ├── router.gleam     # /, /static/*, /health, /ws
│   │       ├── ws.gleam         # WebSocket-обробник на кожного клієнта
│   │       ├── hub.gleam        # pub/sub-актор, список підписників
│   │       ├── telemetry.gleam  # метрики VM раз на 1 с
│   │       ├── config.gleam     # env: PORT, SHIP_NAME
│   │       └── ship/
│   │           ├── supervisor.gleam
│   │           └── subsystem.gleam
│   ├── priv/static/             # сюди потрапляє зібраний клієнт + styles.css
│   └── test/
└── client/                      # target = "javascript"
    ├── gleam.toml               # shared = { path = "../shared" }
    ├── src/
    │   ├── client.gleam         # main: lustre.application
    │   └── client/
    │       ├── model.gleam
    │       ├── update.gleam
    │       ├── view.gleam
    │       ├── socket.gleam     # підключення, реконект з backoff
    │       ├── route.gleam      # "/" і "/#/kit"
    │       └── ui/              # власна дизайн-система
    │           ├── theme.gleam
    │           ├── animator.gleam
    │           ├── frame.gleam
    │           ├── decipher.gleam
    │           ├── background.gleam
    │           ├── button.gleam
    │           ├── gauge.gleam
    │           ├── sparkline.gleam
    │           └── log.gleam
    └── test/
```

---

## 5. Протокол (`shared/src/shared/protocol.gleam`)

Орієнтир; уточнюй за потреби, але зберігай ідею «все — власні типи, жодних магічних рядків»:

```gleam
pub type SubsystemId {
  Reactor
  Shields
  Navigation
  Comms
  LifeSupport
}

pub type Status {
  Nominal
  Degraded(reason: String)
  Offline
  Rebooting
}

pub type Subsystem {
  Subsystem(
    id: SubsystemId,
    status: Status,
    power: Int,        // 0..100
    load: Int,         // 0..100
    temperature: Int,  // °C
    restarts: Int,
  )
}

pub type VmStats {
  VmStats(
    process_count: Int,
    memory_bytes: Int,
    run_queue: Int,
    schedulers: Int,
    uptime_ms: Int,
  )
}

pub type Severity {
  Info
  Warning
  Critical
}

pub type LogEntry {
  LogEntry(at_ms: Int, severity: Severity, source: String, message: String)
}

pub type ServerEvent {
  Snapshot(ship_name: String, subsystems: List(Subsystem), vm: VmStats, log: List(LogEntry))
  SubsystemUpdated(Subsystem)
  VmUpdated(VmStats)
  Logged(LogEntry)
}

pub type ClientCommand {
  InjectFault(SubsystemId)
  Reboot(SubsystemId)
  SetPower(SubsystemId, level: Int)
}
```

- Кодеки (`codec.gleam`) пишуться вручну через `gleam_json` і `gleam/dynamic/decode`. Формат JSON: `{"type": "...", ...}`.
- Для кожного варіанту `ServerEvent` і `ClientCommand` має бути **roundtrip-тест** (encode → decode = оригінал).

---

## 6. Серверна логіка (OTP)

- **`ship/supervisor`** — стратегія `one_for_one`, по одному дочірньому актору на кожну підсистему. Інтенсивність рестартів задай так, щоб демо з кількома швидкими збоями поспіль не «поклало» весь застосунок.
- **`ship/subsystem`** — актор зі станом `Subsystem`:
  - кожні 500 мс робить невеликий випадковий дрейф load/temperature (через `int.random`), а при перегріві переходить у `Degraded`;
  - `InjectFault` **навмисно падає** (`panic`), а відновлення — це робота супервізора, не самого актора;
  - після старту реєструється в hub і публікує `Rebooting`, потім `Nominal`; лічильник `restarts` зберігається поза актором (наприклад, у hub чи ETS-подібному стані через окремий актор), щоб пережити падіння;
  - `Reboot` — контрольоване перезавантаження без паніки, `SetPower` змінює потужність (clamp 0..100).
- **`hub`** — pub/sub-актор: тримає список підписників (WebSocket-процесів), розсилає `ServerEvent`, зберігає останній знімок і хвіст журналу (останні 200 записів) для `Snapshot` новим клієнтам. Відписує мертві процеси через монітори.
- **`telemetry`** — раз на секунду знімає метрики VM через `@external(erlang, ...)` (`erlang:system_info(process_count)`, `erlang:memory(total)`, `erlang:statistics(run_queue)`, `erlang:system_info(schedulers_online)`, `erlang:statistics(wall_clock)`) і публікує `VmUpdated`.
- **`ws`** — на з'єднанні підписується в hub і відправляє `Snapshot`; вхідні повідомлення декодує в `ClientCommand`. Невалідний JSON логується і ігнорується, з'єднання не падає.
- **`router`**: `GET /` → `index.html`; `GET /static/*` → файли з `priv/static`; `GET /health` → `200 ok`; `GET /ws` → upgrade. Решта шляхів → 404.
- `let assert` дозволено лише під час старту застосунку; в обробниках запитів усі помилки обробляються через `Result`.

---

## 7. Дизайн-система (натхнення Arwes, власна реалізація)

### 7.1 Токени (`styles.css`, CSS custom properties)

```css
:root {
  --bg: #020a0d;
  --bg-panel: rgba(4, 30, 36, 0.55);
  --primary: #19f3f3;        /* основний неоновий ціан */
  --primary-dim: #0b6e73;
  --accent: #ffd166;         /* попередження */
  --danger: #ff3b5c;         /* збої */
  --success: #3dffa2;
  --text: #c9f8ff;
  --text-dim: #6aa9b0;
  --glow: 0 0 6px var(--primary), 0 0 18px rgba(25, 243, 243, 0.25);
  --font-ui: "Titillium Web", system-ui, sans-serif;   /* шрифт OFL, self-hosted у priv/static/fonts, опційно */
  --font-mono: ui-monospace, "JetBrains Mono", monospace;
  --dur-enter: 400ms;
  --dur-exit: 300ms;
  --stagger: 80ms;
}
```

Теми змінюються лише через ці змінні. Кольори напряму в Gleam-коді не пишемо, тільки через класи й змінні.

### 7.2 Animator (серце системи) — `ui/animator.gleam`

```gleam
pub type Anim {
  Exited
  Entering(progress: Float)  // 0.0..1.0
  Entered
  Exiting(progress: Float)
}
```

- Чисті функції: `enter(anim)`, `exit(anim)`, `tick(anim, dt_ms, duration_ms) -> Anim`, `progress(anim) -> Float`. Усі вони покриті юніт-тестами.
- Тік — один глобальний `requestAnimationFrame`-цикл через Lustre effect (браузерні API через `plinth` або мінімальний FFI). Компоненти не заводять власні таймери.
- Оркестрація: батько вмикає дочірні елементи по черзі з затримкою `stagger`. Дочірній елемент не з'являється, доки батько не дійшов до `Entered`.
- У DOM стан передається як `data-anim="entering"` і CSS-змінна `--p: <progress>`. CSS використовує їх для `stroke-dashoffset`, `opacity` тощо.
- При `prefers-reduced-motion: reduce` усі переходи миттєві: стан одразу стає `Entered`.

### 7.3 Компоненти

| Компонент | Поведінка |
|---|---|
| `background` | Сітка ліній і точкова матриця (CSS gradients), повільна скан-лінія, легка віньєтка. Без JS-анімації. |
| `frame` | SVG-рамка зі зрізаними кутами (варіанти: `corners`, `octagon`, `underline`). Під час появи лінія «малюється» (`stroke-dasharray`/`dashoffset` від `--p`), фон панелі проявляється після лінії. Має варіант `danger`: червоний колір і пульсація. |
| `decipher` | Текст спочатку показується випадковими гліфами (`ABCDEF0123456789#$%&@*+=<>/\`) і розшифровується зліва направо за час `--dur-enter`. Пробіли зберігаються. Детермінований для тестів (seed передається параметром). |
| `button` | Обгорнутий у `frame`, світиться при hover, спалахує при натисканні; має стан `disabled`. Доступний з клавіатури. |
| `gauge` | Сегментована шкала (20 сегментів) для power/load/temperature, колір за порогами (`primary` → `accent` → `danger`). |
| `sparkline` | SVG-лінія останніх 60 точок (пам'ять, процеси), генерується в Gleam. |
| `log` | Термінал журналу: моноширинний шрифт, автопрокрутка, нові рядки з'являються через `decipher`, колір за `Severity`. Має `aria-live="polite"`. |

### 7.4 Макет головної сторінки

- **Header:** назва корабля (`SHIP_NAME`, через decipher), годинник UTC, індикатор з'єднання (`LINK ONLINE` / `LINK LOST — RETRYING`).
- **Ліва колонка:** 5 карток підсистем (frame + gauges + статус + кнопки `REBOOT`, `INJECT FAULT`, повзунок потужності).
- **Центр:** VM telemetry — великі числа і дві sparkline.
- **Права колонка:** журнал подій.
- **Збій підсистеми:** її рамка переходить у `danger`, заголовок розшифровується в `SUBSYSTEM FAILURE`, у журналі з'являється `Critical`-запис. Після рестарту — `Rebooting`, потім `Nominal`.
- **Адаптивність:** від 360 px — одна колонка, від 1024 px — три.
- `/#/kit` — сторінка-вітрина з усіма UI-компонентами в усіх станах. Кожен новий компонент обов'язково з'являється тут.

### 7.5 Поза межами MVP

Звуки (потребували б значного JS FFI), WebGL-ефекти, кілька кораблів, авторизація, збереження стану між рестартами контейнера.

---

## 8. Docker

### Dockerfile (multi-stage)

1. **`build`** — офіційний образ `ghcr.io/gleam-lang/gleam:v<версія>-erlang-<distro>` (зафіксувати точну версію).
   - Копіювати `shared/`, `client/`, `server/`.
   - Зібрати клієнт: `cd client && gleam run -m lustre/dev build ...`. Точну команду й прапорці (minify, outdir) звір з документацією встановленої версії `lustre_dev_tools`. Результат покласти в `server/priv/static/`.
   - `cd server && gleam export erlang-shipment`.
   - Увага: `lustre_dev_tools` може завантажувати бінарник bundler'а (esbuild/bun). Якщо він не працює на Alpine (musl), використай debian-варіант образу Gleam.
2. **`test`** — на базі `build`: `gleam test` у `shared`, `server`, `client`. Для JS-тестів клієнта потрібен Node/Deno/Bun у цьому stage (лише для тестів, не в рантаймі).
3. **`runtime`** — `erlang:<відповідна OTP>-<distro>-slim/alpine`. Копіює лише shipment, працює під non-root користувачем, `EXPOSE 8000`, `CMD ["./entrypoint.sh", "run"]`.

### docker-compose.yml

```yaml
services:
  mission-control:
    build:
      context: .
      target: runtime
    ports:
      - "8000:8000"
    environment:
      PORT: "8000"
      SHIP_NAME: "ISV GLEAMING STAR"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/health"]
      interval: 10s
      timeout: 3s
      retries: 3
    restart: unless-stopped

  test:
    build:
      context: .
      target: test
    profiles: ["test"]
```

(Якщо в рантайм-образі немає `wget`, заміни healthcheck на доступний інструмент або додай його.)

---

## 9. Команди

```bash
# Запуск
docker compose up --build          # → http://localhost:8000

# Тести
docker compose --profile test run --rm test

# Те саме через just (усе виконується в Docker; `just` без аргументів показує всі рецепти)
just up / just up-d / just down / just logs
just test / just fmt / just fmt-check / just check
just ws                            # жива стрічка JSON з /ws (websocat у контейнері)
just gleam <package> <args>        # напр. just gleam server add mist

# Локально без Docker (опційно, потрібні gleam + erlang)
cd shared && gleam test
cd server && gleam test && gleam run
cd client && gleam test
gleam format --check shared server client
```

---

## 10. Етапи (виконувати строго по черзі)

Кожен етап закінчується «зеленим»: `docker compose up --build` працює, тести проходять, `gleam format --check` чистий, компілятор без warnings. Після етапу онови **Status** і зроби окремий коміт.

- **M0 — Каркас.** Три пакети, Dockerfile, compose, `/health`, статична сторінка `MISSION CONTROL` з `styles.css`.
- **M1 — Протокол.** Типи в `shared`, кодеки, roundtrip-тести.
- **M2 — OTP.** Підсистеми, супервізор, hub, telemetry, `/ws` стримить події. Перевірка: `websocat ws://localhost:8000/ws` показує потік JSON.
- **M3 — Клієнт-каркас.** Lustre-застосунок, socket з реконектом (експоненційний backoff до 10 с), Model з даними сервера, «сирий» рендер без стилів.
- **M4 — Дизайн-система.** `animator` (з тестами), `background`, `frame`, `decipher`, `button`, `gauge`, `sparkline`, `log` і сторінка `/#/kit`.
- **M5 — Дашборд.** Повний макет, команди (`InjectFault`, `Reboot`, `SetPower`), сценарій збою і відновлення.
- **M6 — Поліровка.** `prefers-reduced-motion`, доступність (контраст ≥ 4.5:1 для тексту, фокус-стани, `aria-live` для алертів, керування з клавіатури), `README.md` зі скріншотом і поясненням архітектури.

---

## 11. Конвенції коду

- Маленькі модулі. Логіка — у чистих функціях, ефекти (таймери, сокети, IO) — на краях.
- Власні типи замість `String`/`Bool` для доменних станів.
- Публічні функції мають doc-коментарі `///`.
- Імена: `snake_case` для функцій і модулів, `PascalCase` для типів і конструкторів.
- Без `todo` і `echo` у закомічених змінах.
- Тести: чиста логіка (animator, decipher, кодеки, оновлення стану підсистем) покривається юніт-тестами. Актори тестуються через їхні публічні повідомлення.

---

## 12. Як працювати (для Claude)

1. На початку кожного етапу коротко опиши план: які файли й навіщо.
2. Якщо API пакета не збігається з очікуваним — читай hexdocs або `build/packages/<pkg>/src`, а не вгадуй.
3. Після змін збери й протестуй через Docker. Не оголошуй етап завершеним без зеленої перевірки.
4. Якщо рішення суперечить правилам із розділу 2, зупинись і запитай.
5. Онови **Status** нижче.

---

## Status

- [x] M0 — Каркас
- [x] M1 — Протокол
- [x] M2 — OTP
- [x] M3 — Клієнт-каркас
- [x] M4 — Дизайн-система
- [x] M5 — Дашборд
- [x] M6 — Поліровка

Нотатки та прийняті рішення:
- Gleam зафіксовано на 1.19.2, runtime — `erlang:29-slim` (образ Gleam `v1.19.2-erlang`, Debian trixie, OTP 29). Версії: mist 6.0.3, gleam_otp 1.3.0, gleam_erlang 1.3.0, gleam_http 4.5.0.
- Додано `envoy` (читання `PORT`/`SHIP_NAME`): у `gleam_erlang` немає env-API, а FFI — лише в крайньому разі.
- Попередження `Deprecated type used` походять із залежності `gramps` (через mist), не з нашого коду.
- Тести виконуються на етапі збірки stage `test` (включно з `gleam format --check`); `docker compose --profile test run --rm test` друкує `all tests passed`. Для JS-тестів клієнта в `test` ставиться `nodejs`.
- Маршрутизація — чиста функція `router.route` над типом `Route`; шляхи з `..`, `.`-префіксом і `\\` відхиляються.
- `justfile` (за проханням власника) — обгортка над Docker-командами; версія образу Gleam дублюється в ньому і в Dockerfile.
- Протокол: JSON `{"type": "snake_case", ...}`; id підсистем — `reactor|shields|navigation|comms|life_support`; `Status` — вкладений об'єкт з `type`. Декодери повертають `Error` для невідомих `type`/полів, а не падають. `SetPower.level` не валідується кодеком (clamp 0..100 — на сервері).
- Тести `shared` (17, roundtrip усіх варіантів + wire format + невалідні входи) виконуються на обох таргетах: Erlang і JavaScript.
- M2, дерево супервізії: верхній `rest_for_one` (hub → ship supervisor → telemetry → mist), нижній `ship/supervisor` — `one_for_one` з tolerance 20 рестартів / 10 с (витримує 20 швидких INJECT FAULT поспіль). Усі актори мають імена (`names.gleam`), тож адреси переживають рестарт; відправка в мертвий іменований subject панікує, тому `names.send_to_subsystem` перевіряє `process.named` і відкидає команду.
- `restarts` рахує hub: повторна реєстрація підсистеми = рестарт. Hub моніторить pid підсистем і сам публікує `Offline` + `Critical`-запис при падінні; stale pid ігноруються.
- Системні виклики VM — типізовані `@external` на `erlang:*` (без `.erl`). Пороги: перегрів ≥ 82 °C, відновлення ≤ 72 °C (гістерезис). Boot = 1.5 с у `Rebooting`.
- `websocat` не встановлюємо на хост: `just ws` запускає `ghcr.io/vi/websocat:nightly` з `--network host`.
- Вердикт перевірки M2: `just ws` показує Snapshot + потік подій; сміттєвий JSON ігнорується; 20 швидких збоїв не валять застосунок.
- M3: lustre 5.7.1, lustre_dev_tools 2.4.0 (dev), lustre_websocket 1.1.0, plinth 0.11.0 (таймер реконекту; у M4 — requestAnimationFrame і годинник). Додано поза початковим списком стеку: `lustre_websocket` (WebSocket без власного FFI) — обґрунтування: правило 2, спершу готовий пакет.
- Збірка клієнта в Dockerfile: `gleam run -m lustre/dev build --no-html --minify --outdir=../server/priv/static` → `/static/client.js` (`--outdir` рахується від кореня пакета, не від cwd). lustre_dev_tools сам завантажує `bun` у `client/.lustre/` під час збірки образу (потрібен інтернет); `index.html` залишається нашим (`#app` + module script). `client.js` і `.lustre/` в `.gitignore`/`.dockerignore`.
- Реконект: `Model.attempts` скидається лише в `OnOpen`; затримка 0.5 с · 2^n, максимум 10 с (`socket.backoff_ms`). Msg/Model разом у `client/model.gleam`, щоб `socket` і `update` не імпортували один одного циклічно.
- Перевірка M3: Chromium (`zenika/alpine-chrome`, `--headless=new --virtual-time-budget`) у Docker рендерить `LINK ONLINE`, 5 підсистем, VM-метрики й журнал зі Snapshot. Реконект у браузері перевірено лише юніт-тестами (стан `Lost`, зростання `attempts`), не наскрізно.
- M4, animator: `Anim` + чисті `enter/exit/tick/progress`; `enter`/`exit` під час зворотного руху стартують із поточної видимості (без стрибків), `tick` з `duration <= 0` завершує одразу (так виражається reduced motion — підключення в M6). `Stage` — батько + діти зі `stagger`: діти стартують лише з тіку *після* того, як батько став `Entered`. `Registry` (Dict) тримає лише анімації «в польоті»; відсутній ключ = `Entered`, тож завершені записи видаляються.
- Єдиний rAF-цикл: `Model.loop_running` + `Frame(ts)`; цикл запускається, коли щось анімується (нова log-лінія, зміна маршруту, кнопки kit), і сам зупиняється, коли все осіло. `dt` обмежений 100 мс (повернення з фонової вкладки не «перемотує» анімацію).
- Frame: кожна сторона — окремий SVG, що розтягується лише вздовж своєї осі (товщина лінії не спотворюється); зрізані кути й дужки — маленькі SVG фіксованого розміру. Сегмент `--i` із `--n` малюється у своїй частці `--p` (`stroke-dashoffset: calc(1 - clamp(0, var(--p) * var(--n) - var(--i), 1))`). Перша спроба (один path + `preserveAspectRatio="none"` + `non-scaling-stroke`) ламала штрихи й товщину — виявлено скриншотом у Chromium.
- `plinth` `location.hash` повертає хеш БЕЗ `#` і декодований, тому `route.parse` приймає обидві форми.
- Log: `column-reverse` + DOM «найновіший першим» дає автопрокрутку без JS; `role="log"`, `aria-live="polite"`.
- Тривалості в Gleam (`theme.enter_ms` тощо) дзеркалять CSS-токени; тест фіксує значення. Кольорів у Gleam-коді немає — лише класи/змінні.
- Перевірка M4: скриншоти Chromium у Docker через DevTools-протокол (скрипт не в репо). Режим `--screenshot` зависає на сторінках із нескінченними анімаціями, а висота вікна > ~1500 px дає `Internal error`; тому знімали 1280x900 зі скролом.
- Стан після M4: shared 18 (×2 таргети), server 37, client 97 тестів. Дашборд `/` ще «сирий» (M5).
- M5, команди: `Operate(ClientCommand)` → `socket.send` (JSON через `codec.encode_command`); повзунок потужності шле `SetPower` на `change` (відпускання), а не на `input`, щоб не засмічувати журнал. Без відкритого сокета команда мовчки відкидається (кнопки при цьому disabled). Правила активності кнопок — чисті функції в `dashboard.gleam` (`can_reboot`, `can_inject_fault`, `can_set_power`).
- Стан збою: `Offline` триває мілісекунди (супервізор перезапускає одразу), тому клієнт тримає `Model.failed`: підсистема «в аварії» від `Offline` (або зростання `restarts`) до повернення в `Nominal`; контрольований `Reboot` аварією не є. Картка весь цей час `danger`, заголовок — `SUBSYSTEM FAILURE` (decipher при вході й при поверненні назви). Snapshot перераховує `failed` з нуля.
- Назва корабля розшифровується лише коли вперше приходить (або змінюється); при реконекті з тією ж назвою не програється. Годинник UTC — `plinth` `set_interval`, форматери (`format.gleam`) чисті.
- `button.view` отримав `describing` (aria-label), бо на сторінці п'ять кнопок REBOOT. Статус картки має `aria-live="polite"`.
- Шкала POWER фарбується за тими ж порогами, що й load/temp (як у розділі 7.3), тому нормальні 90 % Reactor червоні. Якщо це заважає, то POWER можна зробити нейтральним — рішення за власником.
- Перевірка M5 у Chromium (Docker, DevTools): дашборд 3 колонки / 1 колонка; клік INJECT FAULT → червона рамка, SUBSYSTEM FAILURE, REBOOTING, `[CRIT]` у журналі → через ~2 с NOMINAL і назва назад; повзунок → POWER SET TO у журналі.
- Стан після M5: shared 18 (×2), server 37, client 122 тести.
- M6, reduced motion: `Model.reduced_motion` (початкове значення й зміни наживо з `matchMedia`) → тривалості та `stagger` = 0, `tick` завершує перехід за наступний кадр, без розшифрування. Єдиний ручний JS у клієнті — `client/src/client/reduced_motion_ffi.mjs` (≈15 рядків, з поясненням): `matchMedia` — єдиний спосіб прочитати налаштування, а в `plinth`/Lustre його немає.
- Контраст (рахунок WCAG для всіх токенів на фоні сторінки, панелі, логу й danger-панелі): усі ≥ 4.5:1; натиснута danger-кнопка спершу давала 3.3:1, тому `:active` = 16 % підсвітки (≈ 4.7:1) + масштаб/яскравість. Disabled-елементи за WCAG звільнені від вимоги.
- Доступність: `role="alert"` (прихований, `SUBSYSTEM FAILURE: <імена>`), `role="status"` для лінку, `aria-live="polite"` для статусів, `tabindex=0` на логу, єдине кільце фокуса, унікальні імена кнопок. Перевірено в Chromium (Docker, DevTools): власний аудит DOM (імена, tabindex, id, meter, live-регіони) без зауважень; справжня клавіатура: Tab → повзунок → REBOOT → INJECT FAULT, стрілка змінює потужність, Enter запускає збій, alert оголошується й очищується після відновлення; з емуляцією reduced motion усе `entered` вже через 0.45 с.
- axe-core спробували завантажити з CDN для автоаудиту, але політика середовища заборонила виконання стороннього коду; замінено власним аудитом. Автоматичний axe можна запустити вручну поза цією сесією.
- README.md: скріншоти (`server/priv/static/screenshot*.png`), архітектура, протокол, дизайн-система, доступність. Усі публічні функції й типи мають `///` (розділ 11); згенерований `shared/src/shared.gleam` з `main` видалено.
- Фінал: чиста збірка без кешу, `docker compose up --build` → healthy, тести shared 18 (×2), server 37, client 129, `gleam format --check` чистий.
