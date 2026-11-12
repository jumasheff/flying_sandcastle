# Staging: Fly.io + өзүнчө Supabase

Фабрика ар бир run'да `main`'ди текшерет. `main` өзгөрсө:
1. жаңы Supabase миграцияларын **staging** базасына колдонот;
2. `turna-staging` Fly app'ына deploy кылат: `https://turna-staging.fly.dev`.

GitHub Actions'тын кереги жок: deploy'ду Hetzner сервери өзү жасайт. Build Fly'дын remote builder'инде жүрөт, ошондуктан сервер жүктөлбөйт.

**Эмне үчүн өзүнчө Supabase:** пилоттун базасында чыныгы окуучулардын маалыматы жана ата-энелердин макулдугу сакталат. Staging болсо агент жазган, али текшерилбеген кодду иштетет. Ошондуктан staging жана production эч качан бир базаны бөлүшпөйт. Staging'дин Fly токени production app'ына да жетпейт.

Staging'де AI өчүк, анткени ага `ANTHROPIC_API_KEY` берилбейт (`src/lib/ai.ts`). Ошентип staging AI үчүн акча коротпойт. AI'ды сынап көрүү керек болсо, Anthropic Console'до чыгым лимити коюлган өзүнчө ачкыч түзүп, муну иштетиңиз:

```bash
fly secrets set ANTHROPIC_API_KEY=... -a turna-staging
```

---

## Бир жолку орнотуу (болжол менен 20 мүнөт)

### 1. Supabase staging долбоору

1. supabase.com → **New project** → аты: `turna-staging`, регион: **Central EU (Frankfurt)**. Бекер план жетиштүү.
2. **Database password**'ду сактап коюңуз.
3. **Authentication → URL Configuration:**
   - Site URL: `https://turna-staging.fly.dev`
   - Redirect URLs: `https://turna-staging.fly.dev/auth/confirm`
4. **Settings → API:** Project URL жана **Publishable key**'ди көчүрүп алыңыз.
5. **Connect → Session pooler → URI:** сырсөзү менен көчүрүп алыңыз. Бул `STAGING_DB_URL` болот.

### 2. Биринчи миграциялар жана демо маалымат

Муну өз компьютериңизде же серверде, `turna` репосунун ичинде иштетиңиз:

```bash
npx -y supabase@3 db push --remote="postgresql://postgres.xxx:PASSWORD@aws-0-eu-central-1.pooler.supabase.com:5432/postgres" --skip-vault --yes
```

```bash
SUPABASE_URL=https://<staging-ref>.supabase.co SUPABASE_SECRET_KEY=sb_secret_... npm run seed:demo
```

Демо аккаунттардын тизмеси `DEPLOY.md`'нин 4-бөлүмүндө. Кофаундер staging'ге ошол аккаунттар менен кирет.

### 3. Fly app жана токен

```bash
fly apps create turna-staging
```

Бул токен **staging app'ына гана** жетет:

```bash
fly tokens create deploy -a turna-staging
```

### 4. Серверге жазуу

```bash
nano /etc/factory/factory.env
```

`STAGING_APP=turna-staging`, `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_PUBLISHABLE_KEY` маанилерин жазыңыз.

```bash
nano /etc/factory/host-secrets.env
```

`FLY_API_TOKEN` жана `STAGING_DB_URL` маанилерин жазыңыз (URL'ду тырмакчага алыңыз). Бул файл агенттерге **берилбейт**.

### 5. Биринчи deploy

```bash
sudo -u factory -H bash -c 'set -a; . /etc/factory/factory.env; . /etc/factory/host-secrets.env; set +a; cd /var/lib/factory/project && WORK_DIR=/var/lib/factory FORCE=1 /opt/factory/scripts/deploy-staging.sh'
```

Мындан ары staging ар бир run'да өзү жаңыланат (ар 20 мүнөттө, `main` өзгөргөн болсо).

---

## Production

Production (`turna-ai`) мурункудай эле **кол менен** deploy кылынат. Адегенде миграцияларды production базасына колдонуп, анан deploy кыласыз:

```bash
npx supabase db push --remote
```

```bash
fly deploy
```

PR'да жаңы миграция болсо, фабрика PR'га эскертүү жазат.

## Белгилүү чектөөлөр

- Бекер Supabase долбоору бир жума колдонулбаса, убактылуу токтоп калат. Аны dashboard'дан **Restore** баскычы менен кайра иштетесиз.
- Staging машинасы колдонулбаганда токтоп турат. Ошондуктан биринчи ачылышы бир нече секундга созулат.
- Staging'дин бир базасы бар. Миграциялар ага PR merge болгондон кийин гана колдонулат.
