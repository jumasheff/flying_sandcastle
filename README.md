# Flying Sandcastle

[Sandcastle](https://github.com/mattpocock/sandcastle) (Matt Pocock) негизинде курулган программа "фабрикасы". Бир арзан Hetzner серверинде иштейт:

**GitHub issue → агенттер (Claude Code, Docker ичинде) → Pull Request → сиз merge кыласыз.**

```
Телефон / PC ──▶ GitHub: issue + `ready-for-agent` label
                     │
Hetzner VPS ── systemd timer (ар 20 мүнөт) ── scripts/run.sh
                     │
                     ├─ 1. Planner (opus): кайсы issue'лар параллель жасалат?
                     ├─ 2. Ар бир issue → өзүнчө Docker sandbox + branch `sandcastle/issue-N`
                     │      implementer (sonnet) → reviewer (sonnet)
                     └─ 3. push → PR "Closes #N" → issue: `sandcastle:in-review`
```

## Label'дер

| Label | Мааниси | Ким коёт |
|---|---|---|
| `needs-triage` | Жаңы идея, сиздин карооңузду күтөт | Кофаундер (issue-intake) |
| `ready-for-agent` | Иштөөгө даяр | Сиз |
| `sandcastle:in-review` | PR ачылды, сиздин review'ду күтөт | Фабрика |
| `sandcastle:needs-human` | Агент токтоп калды, issue'нун комментарийлерин окуңуз | Фабрика |

Label'дер Matt Pocock'тун triage label'дерине дал келет (`docs/agents/triage-labels.md`). Жетишпегендерин фабрика биринчи иштегенде өзү түзөт, ал эми бар label'дерге тийбейт.

---

## Орнотуу (болжол менен 30 мүнөт)

### 0. Долбоордун репосу

Next.js долбоорунун GitHub репосунда (мисалы `turna`) `main` branch'ында жок дегенде бир commit болушу керек. Репо бош болсо, GitHub'да репону түзүп жатканда "Add a README" белгисин коюңуз. Next.js'ти агенттин өзү түзө алат: биринчи issue катары "Next.js App Router + TypeScript + Vitest долбоорун түз" деп жазыңуз.

Кеңеш: репонун түбүнө `CLAUDE.md` файлын кошуңуз. Ага долбоордун эрежелерин жазыңуз. Агенттер аны ар дайым окушат.

### 1. GitHub токени

<https://github.com/settings/personal-access-tokens/new> → **Fine-grained token**:
- Repository access: **Only select repositories** → долбоордун репосу гана
- Permissions: **Contents**, **Pull requests**, **Issues**: *Read and write*; **Metadata**: *Read*

### 2. Hetzner сервери

[console.hetzner.cloud](https://console.hetzner.cloud) → New server:
- **Type:** CX33 (4 vCPU, 8 GB RAM, x86) — болжол менен айына €6–8. Учурдагы бааны сайттан текшериңиз.
- **Image:** Ubuntu 24.04
- **SSH key:** ачык ачкычыңызды кошуңуз
- **Cloud config:** [`infra/cloud-init.yaml`](infra/cloud-init.yaml) файлын чаптаңыз. Бул репо *private* болсо, файлдагы `runcmd` бөлүгүн өчүрүп, 3-кадамды кол менен аткарыңыз.

### 3. Серверге кирүү жана орнотуу

```bash
ssh root@<SERVER_IP>
```

Cloud-init бүткөнүн текшериңиз (2–5 мүнөт):

```bash
tail -f /var/log/factory-setup.log
```

Cloud-init колдонбосоңуз же репо private болсо, кол менен орнотуңуз:

```bash
git clone https://github.com/jumasheff/flying_sandcastle.git && cd flying_sandcastle && ./infra/setup.sh
```

### 4. Жөндөөлөр

```bash
nano /etc/factory/factory.env
```

`TARGET_REPO=owner/turna` деп долбоордун репосун жазыңуз.

Claude Max токенин алыңыз. Серверде иштетиңиз, ал шилтеме берет. Шилтемени телефондон же PC'ден ачып, кодду кайра чаптаңыз:

```bash
npx -y @anthropic-ai/claude-code setup-token
```

```bash
nano /etc/factory/secrets.env
```

Ага `CLAUDE_CODE_OAUTH_TOKEN` жана `GH_TOKEN` жазыңуз.

### 5. Биринчи ишке киргизүү

Биринчи run'ду кол менен иштетиңиз. Ал жетишпеген label'дерди түзөт жана "No issues labelled 'ready-for-agent'" деп бүтөт:

```bash
systemctl start factory && journalctl -u factory -f
```

Андан кийин долбоордо бир issue түзүп, ага `ready-for-agent` label'ин коюп, кайра иштетиңиз. Бул жолу Docker image build болот, ага 3–5 мүнөт кетет:

```bash
systemctl start factory && journalctl -u factory -f
```

Баары иштесе, таймерди күйгүзүңүз:

```bash
systemctl enable --now factory.timer
```

### 6. Телефондон кирүү (Tailscale)

Серверде:

```bash
tailscale up --ssh
```

Телефонго **Tailscale** жана **Termius** колдонмолорун орнотуп, бир аккаунт менен кириңиз. Андан кийин серверге `ssh root@<tailscale-аты>` менен кошуласыз. Көп учурда серверге кирүүнүн кереги жок: **GitHub** колдонмосу жетиштүү.

Кошумча коопсуздук: Tailscale иштеп калгандан кийин, Hetzner Cloud Firewall'до 22-портту жаап койсоңуз болот.

---

## Күнүмдүк иш

1. **Тапшырма:** GitHub'да issue жазасыз. Эмне керек, кандай болушу керек, кайсы issue'дан көз каранды экенин ("Blocked by #3" же GitHub'дагы "Blocked by" байланышы) жазыңуз. `ready-for-agent` label'ин коёсуз.
2. **Күтүү:** 20 мүнөттүн ичинде фабрика ишти баштайт. Бүткөндө issue'га PR шилтемеси келет.
3. **Review:** PR'ды карайсыз. Жакса → **Merge**, issue өзү жабылат.
4. **Өзгөртүү керек болсо:** PR'га комментарий жазып, issue'га `ready-for-agent` label'ин кайра коёсуз. Агент комментарийлерди окуп, ошол эле branch'ты улантат.
5. **`sandcastle:needs-human`:** агенттин issue'дагы комментарийин окуп, issue'ну тактап, `ready-for-agent` label'ин кайра коюңуз.

Issue'лар бири-биринен көз каранды болсо, planner алардын тартибин сактайт. Мисалы, #5 #3'кө көз каранды болсо, #3'түн PR'ы merge болмоюнча #5 башталбайт.

## Staging

`main` өзгөргөн сайын фабрика аны `turna-staging`'ге deploy кылат жана миграцияларды өзүнчө staging Supabase базасына колдонот. GitHub Actions'тын кереги жок. Орнотуу тартиби [docs/staging.md](docs/staging.md) файлында.

## Кофаундер / командалаш

Техникалык эмес командалашыңыз iPhone'дон үн менен идея айтып, issue түзө алат. Кантип жөндөө керектигин [docs/cofounder.md](docs/cofounder.md) файлынан караңыз.

## Пайдалуу буйруктар

Азыр иштеп жатабы, акыркы логдор:

```bash
systemctl status factory; journalctl -u factory -n 100
```

Азыр кол менен иштетүү:

```bash
systemctl start factory
```

Агенттердин толук логдору:

```bash
ls -t /var/lib/factory/project/.sandcastle/logs/
```

Фабриканы токтотуу:

```bash
systemctl disable --now factory.timer
```

Фабриканы жаңыртуу (бул репонун жаңы версиясы):

```bash
cd ~/flying_sandcastle && git pull && ./infra/setup.sh
```

Башка долбоорго өтүү: `factory.env`'де `TARGET_REPO`'ну өзгөртүп, эски клонду өчүрүңүз:

```bash
rm -rf /var/lib/factory/project
```

## Жөндөөлөр ([`factory.env.example`](factory.env.example))

| Өзгөрмө | Демейки | Түшүндүрмө |
|---|---|---|
| `MAX_PARALLEL` | `2` | Бир убакта канча issue. CX33 үчүн 2–3. |
| `PLANNER_MODEL` | `opus` | Пландоочу модель |
| `IMPLEMENTER_MODEL`, `REVIEWER_MODEL` | `sonnet` | Код жазуучу жана текшерүүчү модель |
| `IMPLEMENTER_MAX_ITERATIONS` | `30` | Бир issue'га канча итерация |

## Чыгымдар жана лимиттер

- **Сервер:** айына болжол менен €6–8 (Hetzner CX33).
- **Claude:** Max жазылуусунун лимити колдонулат. Ал сиздин кадимки Claude Code колдонууңуз менен **бөлүшүлөт**. Лимит бүтсө, run катага учурайт, label өзгөрбөйт, кийинки run кайра аракет кылат.
- `ready-for-agent` label'и бар issue жок болсо, агенттер таптакыр иштебейт, лимит коротулбайт.

## Коопсуздук

- Агенттер Docker контейнеринде иштешет жана сервердин файлдарын көрүшпөйт. Контейнерге `CLAUDE_CODE_OAUTH_TOKEN` жана `GH_TOKEN` гана берилет.
- GitHub токени бир гана репого жетет. Агенттер `main`'ге push кылбайт: push'ту жана PR'ды хост тарабы жасайт, merge'ди сиз жасайсыз.
- Кошумча: GitHub'да `main` үчүн branch protection күйгүзүңүз (Settings → Branches).

## Файлдар

| Файл | Эмне |
|---|---|
| `sandcastle/main.mts` | Оркестрация: plan → implement → review → PR |
| `sandcastle/*-prompt.md` | Агенттердин промпттору |
| `sandcastle/Dockerfile` | Sandbox image (Node 22, gh, Claude Code) |
| `scripts/run.sh` | Бир run: репону жаңыртуу, label'дер, staging, image, `main.mts` |
| `scripts/deploy-staging.sh` | `main` → staging: миграциялар + `fly deploy` |
| `infra/setup.sh` | Серверди орнотуу (Docker, Node, gh, flyctl, Tailscale, systemd) |
| `infra/cloud-init.yaml` | Hetzner'де сервер түзүп жатканда чапталат |
| `infra/factory.service`, `.timer` | systemd: ар 20 мүнөттө бир run |
| `templates/project/` | Долбоордун репосуна көчүрүлүүчү файлдар (`issue-intake` skill) |
| `docs/cofounder.md` | Кофаундерди кошуу боюнча нускама |
| `docs/staging.md` | Staging'ди орнотуу (Fly + өзүнчө Supabase) |
