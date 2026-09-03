---
name: webinar-domaine-envoi
description: "Preparer un domaine d'envoi webinar de bout en bout : ajout au Google Workspace dedie (nexrai), verification, MX/SPF/DKIM/DMARC chez Gandi, compte expediteur, verdict pret/pas pret. Utilise /webinar-domaine-envoi pour configurer un domaine achete pour les campagnes d'invitations."
---

# Webinar — preparer un domaine d'envoi

Reproduit le setup fait manuellement au Tech Call du 19/08/2026 avec Jose Velez
(aileadwebinar.com) : le domaine achete chez Gandi devient un domaine d'envoi
operationnel du Google Workspace DEDIE aux campagnes.

## Le decor, a connaitre avant de toucher

- **Deux Workspaces distincts.** Le Workspace CIBLE est celui de nexrai (ancien
  espace, >100 $ payes → limite d'envoi ~200 invitations/jour/domaine). Le
  Workspace 5000.dev de la connexion Google normale de la plateforme N'EST PAS
  concerne. Les tools `google_workspace_*` utilisent un token dedie (tenant
  credential `google_workspace_admin_refresh_token`) : ne JAMAIS tenter le setup
  avec la connexion utilisateur.
- **Limites Google** : un Workspace neuf est bride a ~49 invitations/jour
  pendant 60 jours. C'est la raison du choix du vieil espace.
- **Architecture de la campagne** (contexte) : 6 domaines pour les invitations
  calendrier + 1 pour les emails de suivi GoHighLevel ; Hermes connecte les
  comptes Google et synchronise avec WebinarGeek.

## Setup initial (UNE fois, humain)

Si un tool rend « credential google_workspace_admin_refresh_token absente » :
`bin/rails runner bin/google-workspace-admin-consent` sur le serveur, connexion
avec le compte SUPER-ADMIN du Workspace nexrai, coller le code. Le script
verifie l'email du compte avant d'ecrire quoi que ce soit.

## Le runbook, domaine par domaine

1. **Prerequis** : le domaine est au compte Gandi (sinon `gandi_check_domain`
   puis `gandi_register_domain`, avec ses propres gardes).
2. **`google_workspace_add_domain(domain: "...")`** — fait d'un coup : domaine
   secondaire, jeton de verification, TXT chez Gandi, verification (retente ~3
   min), MX `1 smtp.google.com.`, SPF, DMARC (`p=none` pour commencer, choix du
   call : observer avant de durcir).
   - `verification: pending_propagation` n'est PAS un echec : la propagation
     DNS prend son temps. On repasse par domain_status plus tard.
   - `spf: CONFLICT_not_touched` = un SPF etranger existe : fusion A LA MAIN,
     jamais d'ecrasement.
3. **Les deux gestes humains**, a signaler a l'utilisateur avec les liens :
   - DKIM : console admin → https://admin.google.com/ac/apps/gmail/authenticateemail
     → selectionner le domaine → generer → le TXT `google._domainkey` se pose
     chez Gandi si la console le donne (sinon `gandi_create_dns_record`).
   - Gmail : activer pour le domaine si la console le demande.
4. **`google_workspace_domain_status(domain: "...")`** — le verdict, mesure sur
   les DNS PUBLICS (ce que Google voit, pas ce que Gandi croit).
   **REGLE ABSOLUE : aucun envoi, aucune campagne, aucun compte declare pret
   tant que `ready` n'est pas true.** Un domaine a moitie configure brule sa
   reputation d'envoi, et une reputation ne se repare pas en re-posant un TXT.
5. **`google_workspace_create_user(...)`** pour le compte expediteur — SIEGE
   PAYANT : dry run d'abord, montrer a l'humain, `confirm: true` seulement
   apres son accord. Le mot de passe temporaire s'affiche UNE fois.

## Discipline

- Un domaine a la fois, status vert avant de passer au suivant.
- Les etats intermediaires se rapportent avec la grille ETAT (CLAUDE.md) : ce
  qui est fait, ce qui propage, ce qui attend un clic humain.
- Ne pas inventer de valeurs DNS : celles du tool sont celles du call (MX
  smtp.google.com moderne unique, SPF include _spf.google.com, DMARC p=none).
