# ugreen-hal — repères pour Claude Code

Ce fichier n'est qu'un pointeur technique (format imposé par Claude Code). Tout le contenu de fond du projet vit exclusivement en AsciiDoc — ne pas dupliquer de contenu ici, seulement mettre à jour les pointeurs si l'arborescence change.

## À lire en premier, dans cet ordre

1. `README.fr.adoc` — présentation du projet, objectifs, matériel de référence (UGREEN NASync DXP2800).
2. `docs/plan-firmware-freebsd-ugreen-nas.adoc` — plan de projet de référence (stable) : phases, sprints, architecture (cœur `src/cli/` indépendant de la distribution + `integrations/zvault/` et `integrations/xigmanas/`), risques identifiés.
3. `docs/journal.adoc` — journal daté (vivant) : décisions prises, état d'avancement réel, prochaines étapes. **Toujours consulter la dernière entrée avant de reprendre le travail.**
4. `docs/catalogue-nas-ugreen.adoc` — catalogue comparatif des NAS UGREEN et recommandations d'achat (matériel de test).
5. `docs/hardware-notes.adoc` et `docs/protocol-i2c-leds.adoc` — relevés matériels bas niveau (chipsets, protocole SMBus du contrôleur LED).
6. `CONTRIBUTING.adoc` — conventions de contribution (rigueur des sources, format AsciiDoc obligatoire).

## Conventions du projet, à respecter systématiquement

* Tous les documents sont en AsciiDoc (`.adoc`), jamais en Markdown, à l'exception de ce fichier `CLAUDE.md` (contrainte de l'outil).
* Chaque relevé matériel ou affirmation technique doit citer sa source (voir `CONTRIBUTING.adoc`).
* `docs/journal.adoc` doit être mis à jour à la fin de chaque session de travail (voir « Continuité du travail entre les sessions » dans le plan).
* Licence BSD-2-Clause ; auteur/copyright : Philippe Nénert (ALOLI sas).
* Stratégie double cible (v1.8) : le cœur du HAL (`src/cli/`) reste strictement FreeBSD standard (`smbus(4)`/`gpio(4)`), sans connaissance de zVault ou XigmaNAS ; l'intégration à chaque distribution vit dans une couche fine séparée (`integrations/zvault/`, `integrations/xigmanas/`), ajoutée une fois le cœur validé. zVault en premier, XigmaNAS ensuite (ordre confirmé).

## Répartition des rôles (rappel du plan)

Cet assistant n'a pas d'accès physique au NAS (pas de bus I2C, pas de port série). Il écrit et revoit le code, la documentation et les scripts ; l'exécution physique sur le matériel réel (compilation, flash, observation d'une LED, branchement de disques) reste entre les mains de l'utilisateur, qui retranscrit les résultats.
