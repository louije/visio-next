<div align="center">
  <img src="docs/icon.png" width="128" alt="Icône VisioNext">
  <h1>VisioNext</h1>
  <p>Une liste des visios à venir dans la barre de menus macOS.</p>
  <p>
    <a href="https://github.com/louije/visio-next/releases/latest/download/VisioNext.dmg">
      <b>⬇️&nbsp;&nbsp;Télécharger VisioNext</b>
    </a>
    <br>
    <sub>macOS 14 ou plus récent · libre</sub>
  </p>
</div>

---

VisioNext liste les prochaines réunions (depuis le Calendrier macOS) et permet de les rejoindre
d'un clic. Plein d'autres applications font ça (sûrement). Celle-ci a la particularité de gérer les
liens de l'application Viso de LaSuite (visio.numerique.gouv.fr).

> [!IMPORTANT]
> Contamination IA : ce projet a été développé avec l'aide de modèles de langage
> (outils de programmation assistés par IA).

## Fonctionnalités

- Icône dans la barre des menus
- Génération de liens Visio personnalisables
- Widget macOS
- Extension Safari qui améliore la mise en page de Visio lors de partages d'écran
- Raccourci global (et micro dans la barre des menus) pour couper le micro de toutes les visios
  ouvertes dans Safari, Chrome ou Firefox (avec l'extension) : Visio, et Google Meet ou Teams
  si vous les autorisez

## Installation

1. **[Télécharger VisioNext](https://github.com/louije/visio-next/releases/latest/download/VisioNext.dmg)**.
2. Ouvrir le fichier `.dmg`, puis glisser **VisioNext** dans le dossier **Applications**.
3. Lancer VisioNext et autoriser l'accès au calendrier au premier démarrage.

L'application tourne localement, et ne récupère aucune statistique d'utilisation. Des appels réseaux
sont émis pour vérifier si une mise à jour est disponible.

---

## Pour les développeurs

### Architecture

- `VisioCore/` — paquet SwiftPM contenant toute la logique métier (testée).
- `App/` — l'app SwiftUI de barre de menus. Le projet Xcode est généré depuis
  `App/project.yml` avec [XcodeGen](https://github.com/yonsm/XcodeGen) et n'est **pas**
  versionné.

### Compiler

```sh
# une seule fois
brew install xcodegen

# générer le projet Xcode
cd App && xcodegen generate

# compiler en ligne de commande (sans signature)
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

# lancer les tests du paquet
cd ../VisioCore && swift test
```

Pour lancer l'app : `open App/VisioNext.xcodeproj`, choisissez votre équipe de
signature dans Signing & Capabilities, puis Run. Autorisez l'accès au calendrier au
premier démarrage.

### Installer en local

```sh
Scripts/install.sh   # compile, signe (Apple Development), installe dans ~/Applications, lance
```

La signature Apple Development (automatique) est utilisée ici pour que l'App Group
du widget soit provisionné et que l'accès au calendrier (TCC) persiste entre les
compilations.

### Publier une version (mise à jour auto via Sparkle)

Les versions sont signées Developer ID, notarisées, signées EdDSA pour Sparkle,
publiées en Release GitHub, et annoncées via un appcast sur GitHub Pages.

```sh
Scripts/release.sh X.Y.Z
```

Le script incrémente la version dans `project.yml`, archive et exporte avec
provisioning Developer ID automatique, notarise et estampille **l'app et le DMG**,
puis crée une Release GitHub avec le **DMG** (le téléchargement grand public,
toujours accessible via `releases/latest/download/VisioNext.dmg`) et le **zip** (pour
les mises à jour Sparkle), et publie l'appcast sur `gh-pages`. Il vérifie chaque
prérequis ci-dessous et s'arrête tôt avec un message clair si l'un manque.

#### Prérequis (une seule fois)

- Certificat **Developer ID Application** dans le trousseau (équipe `684SSZLSSG`).
- Profil **notarytool** nommé `visio-notary` :
  `xcrun notarytool store-credentials visio-notary`
  (identifiant Apple + mot de passe d'application, ou clé App Store Connect).
- **[create-dmg](https://github.com/sindresorhus/create-dmg)** : `npm install --global create-dmg`.
- Clé **Sparkle EdDSA** dans le trousseau (la clé publique est déjà dans `Info.plist`
  via `SUPublicEDKey`, générée une fois avec `generate_keys` de Sparkle). La clé
  privée ne quitte jamais le trousseau et n'est jamais versionnée.
- **`gh`** authentifié (`gh auth status`).
- **GitHub Pages** actif sur la branche `gh-pages` (racine) — il héberge
  `appcast.xml` ; `SUFeedURL` vaut `https://louije.github.io/visio-next/appcast.xml`.

## Licence

Le code de ce projet est publié sous licence **MIT** (voir [`LICENSE`](LICENSE)).

VisioNext est un projet indépendant, non affilié à DINUM, à La Suite numérique, ni
aux éditeurs des services listés. La licence MIT couvre le code, **pas** les
marques et logos ci-dessous :

- Les logos des services (Zoom, Google Meet, Microsoft Teams, Jitsi, Webex,
  BigBlueButton) sont des marques de leurs détenteurs respectifs, inclus
  uniquement pour identifier ces services. Fichiers issus de
  [Simple Icons](https://simpleicons.org) (CC0-1.0) le cas échéant — la licence
  CC0 porte sur les fichiers, pas sur les marques.
- Le logo « Visio » provient du service public
  [visio.numerique.gouv.fr](https://visio.numerique.gouv.fr) (La Suite numérique,
  État français) et reste la propriété de son détenteur ; il identifie le service.
- L'app embarque [Sparkle](https://sparkle-project.org) pour les mises à jour,
  distribué sous sa propre licence.
