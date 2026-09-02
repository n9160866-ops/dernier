# ChatApp iOS — GitHub Actions

Projet Xcode iOS avec `Config.Swift` correctement inclus dans le target `ChatApp`.

## Compilation sans Mac

1. Importez tout le contenu de ce dossier dans votre dépôt GitHub.
2. Ouvrez **Actions**.
3. Sélectionnez **Build iOS app**.
4. Cliquez sur **Run workflow**.
5. À la fin, récupérez l'artifact **ChatApp-iOS-Simulator**.

Le workflow compile pour le simulateur iOS sans signature Apple.

> Pour générer une vraie application installable/signée pour un iPhone ou publier sur l'App Store, il faudra ensuite configurer la signature Apple (certificat, provisioning et compte Apple Developer).
