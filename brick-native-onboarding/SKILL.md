---
name: brick-native-onboarding
description: "Mettre en place le pipeline de soumission mobile (iOS + Android) d'une app cliente Hotwire Native : scaffolder fastlane + GitHub Actions, collecter et poser les secrets de signature, tester sur Appetize, soumettre aux stores. Utilise /brick-native-onboarding quand une app native doit être buildée/soumise automatiquement."
---

# Brick Native Onboarding

Industrialise la soumission d'une app native (coquille Hotwire Native) : build signé
+ upload App Store / Play, en CI, sans build local ni upload manuel. Référence de
travail = **bigpocket** (repo `5000-dev/bigpocket`, branche `mobile-pipeline`) : c'est
le pipeline pilote, copie-le et adapte.

## Quand utiliser

- Une app cliente a un `ios/` (Xcode) + `android/` (Gradle) Hotwire Native.
- On veut builder/soumettre automatiquement (test Appetize, puis stores).

## Principe

Tout le matériel de signature vient de **secrets du repo** → on signe avec les
certifs **du client**. Le même pipeline se copie tel quel d'une app à l'autre :
seuls le bundle id / scheme / package et le contenu des secrets changent.

## Étapes

### 1. Scaffolder les fichiers pipeline

Copie depuis bigpocket (`ios/fastlane/`, `android/fastlane/`, `ios/Gemfile`,
`android/Gemfile`, `.github/workflows/mobile.yml`) et adapte les constantes :

- `ios/fastlane/Fastfile` : `PROJECT` (chemin .xcodeproj), `SCHEME`, `BUNDLE`.
- `android/fastlane/Fastfile` : `AAB`/`APK_DEBUG` paths, `ANDROID_DIR`, package via `Appfile`.
- `android/app/build.gradle.kts` : rendre versionCode/Name surchargeables
  (`-PversionCodeOverride` / `-PversionNameOverride`).
- `mobile.yml` : rien à changer en général (déclencheurs `mobile-test-*` = Appetize
  cert-free, `mobile-v*` = release signé ; job iOS sur `macos-15` = Xcode 26).

### 2. Décider la voie d'auth stores

- **Comptes sous le compte développeur DU CLIENT** (règle : app cliente = compte client,
  cf. Apple 4.2.6). 5000.dev est ajouté Admin.
- **iOS auth** :
  - **Voie A (propre)** : clé API App Store Connect (`ASC_KEY_ID`/`ASC_ISSUER_ID`/
    `ASC_KEY_P8_BASE64`). MAIS seul le **titulaire** du compte peut l'activer.
  - **Voie B (débloque tout de suite, sans le titulaire)** : mot de passe d'app
    (`FASTLANE_USER` + `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`), upload via
    `xcrun altool`. Le clic « Soumettre pour examen » reste MANUEL (App Store Connect).
- **Android** : keystore de release (celui qui a publié) + service account Play.

### 3. Checklist des secrets à poser

**iOS (signature — nécessaire dans les deux voies)** :
| Secret | Où |
|--------|-----|
| `APPLE_TEAM_ID` | developer.apple.com → Membership (10 car. alphanum.) |
| `IOS_DIST_CERT_P12_BASE64` | Trousseau → Mes certificats → « Apple Distribution: … » → Exporter .p12 |
| `IOS_DIST_CERT_PASSWORD` | mot de passe choisi à l'export du .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | developer.apple.com → Profiles → créer un profil **App Store Connect** pour le bundle, Download |
| `IOS_PROFILE_NAME` | nom EXACT du profil |

**iOS auth voie B** : `FASTLANE_USER` (Apple ID email), `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`
(appleid.apple.com → Connexion et sécurité → Mots de passe des apps).
**iOS auth voie A** : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (App Store Connect
→ Users and Access → Integrations → App Store Connect API).

**Android** :
| Secret | Où |
|--------|-----|
| `ANDROID_KEYSTORE_BASE64` | le keystore de release (`storeFile` du keystore.properties local) |
| `ANDROID_STORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` | son keystore.properties |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Cloud → compte de service → clé JSON ; puis Play Console → Utilisateurs → inviter l'email avec droits Releases |

**Commun** : `APPETIZE_API_TOKEN` (dashboard Appetize).

### 4. Collecter et poser les secrets (drag-and-drop + auto-post)

Le client/toi **dépose** les fichiers (cert .p12, keystore, JSON) via la colonne de
droite de /claude → ils atterrissent dans `tmp/dropped/`. Puis ce script les **encode
et les pose** (sealed box, API GitHub — `gh` n'est pas dans le container) :

```ruby
# bin/rails runner - / ou ruby avec le bundle nexrai (rbnacl dispo)
require "rbnacl"; require "base64"; require "net/http"; require "json"
REPO = "5000-dev/APPNAME"                 # <-- repo de l'app
GH   = ENV.fetch("GH_TOKEN")              # token avec accès au repo
def api(m, path, tok, body=nil)
  uri=URI("https://api.github.com#{path}"); k={get:Net::HTTP::Get, put:Net::HTTP::Put}[m]
  r=k.new(uri); r["Authorization"]="Bearer #{tok}"; r["Accept"]="application/vnd.github+json"; r["User-Agent"]="x"
  r.body=body.to_json if body
  res=Net::HTTP.start(uri.host,uri.port,use_ssl:true){|h| h.request(r)}; [res.code.to_i, (JSON.parse(res.body) rescue {})]
end
_, key = api(:get, "/repos/#{REPO}/actions/secrets/public-key", GH)
box = RbNaCl::Boxes::Sealed.from_public_key(RbNaCl::PublicKey.new(Base64.decode64(key["key"])))
put = ->(name, val){ enc=Base64.strict_encode64(box.box(val)); code,_=api(:put,"/repos/#{REPO}/actions/secrets/#{name}",GH,{encrypted_value:enc,key_id:key["key_id"]}); puts "#{name} => #{code}" }
# fichiers → base64 :
put.("IOS_DIST_CERT_P12_BASE64", `base64 -w0 tmp/dropped/xxx.p12`.strip)
put.("PLAY_SERVICE_ACCOUNT_JSON", File.read("tmp/dropped/xxx.json"))
put.("ANDROID_KEYSTORE_BASE64", `base64 -w0 tmp/dropped/xxx.keystore`.strip)
# valeurs simples :
put.("APPLE_TEAM_ID", "XXXXXXXXXX")
# ... etc pour chaque secret
```
Variables (pas secrètes, via `/actions/variables`) : `APPETIZE_PUBLIC_KEY_IOS/ANDROID`
(posées après le 1er upload Appetize pour garder la même URL).
**Toujours** : valider un .p12 (`openssl pkcs12 -legacy -passin pass:… -nokeys`), un profil
(`openssl cms -verify -inform DER -noverify` → Name/bundle/expiration), un JSON
(type=service_account) AVANT de poser. Nettoyer `tmp/dropped/` + tout fichier temp après.

### 5. Tester (Appetize, cert-free)

`git tag mobile-test-1 && git push origin mobile-test-1` → job iOS + Android buildent
en simulateur/debug et uploadent sur Appetize → lien navigateur. Pilotable par agent
via `playwright-cli` (open/goto/click/screenshot). Pose `APPETIZE_PUBLIC_KEY_*` en var
repo avec la publicKey retournée.

### 6. Soumettre

Bumper `MARKETING_VERSION` (iOS) + `versionName` (Android) si la version courante est
déjà publiée. `git tag -f mobile-vX.Y.Z && git push -f origin mobile-vX.Y.Z` :
- iOS → build signé + `altool` upload → App Store Connect (puis clic manuel Soumettre en voie B).
- Android → AAB signé → Play production. Vérifier que la release n'est pas restée en brouillon.

## Pièges connus (déjà corrigés dans bigpocket — copie la version fixée)

- **Apple exige le SDK iOS 26 / Xcode 26** → runner `macos-15` (macos-14 top à Xcode 16.2 = 409).
- **Signature** : `update_code_signing_settings(use_automatic_signing:false, code_sign_identity:"Apple Distribution", …)` sinon Xcode cherche un certif "iOS Development" absent.
- **`__dir__` dans un bloc lane** ≠ dossier fastlane → écrire cert/profil/keystore dans une constante absolue (`BUILD_DIR`), pas `File.join(__dir__, …)`.
- **Android storeFile** : chemin ABSOLU dans keystore.properties (Gradle `file()` résout depuis app/ sinon "keystore not found").
- **Ne pas nommer une lane `appetize`** si elle appelle l'action `appetize` (récursion infinie) → upload API Appetize direct via `curl`.
- **Cache DerivedData** : `actions/cache/restore` + `save(if: always())` pour peupler même sur échec.
- **openssl 3** : `-legacy` pour ouvrir un .p12 exporté de Keychain.
- **`gh` absent du container** : poser les secrets par l'API GitHub (sealed box rbnacl).
- Côté app cliente : `allow_browser versions: :modern` (Rails 8) renvoie 406 à la WebView
  native (iOS < 17.2) → exempter `if: -> { !native_request? }` (UA `Turbo Native`), sur main ET staging.

## Validation gate

- [ ] Fichiers pipeline scaffoldés + adaptés (bundle/scheme/package)
- [ ] Secrets posés et validés (cert, profil, keystore, service account)
- [ ] Test Appetize vert (iOS + Android), lien vérifié
- [ ] Versions bumpées si déjà publié
- [ ] Soumission : iOS sur App Store Connect (+ clic Soumettre), Android sur Play production
- [ ] `tmp/dropped/` et fichiers temp nettoyés
