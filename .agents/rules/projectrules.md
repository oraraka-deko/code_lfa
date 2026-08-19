---
trigger: always_on
---

## only files you should working on them 
- lib\config.dart
- lib\main.dart
- lib\script.dart
- lib\terminal_controller.dart
- lib\terminal_page.dart
- lib\terminal_theme.dart
- lib\utils.dart
- lib\workspace_list_page.dart
- lib\workspace.dart

## most sensetive files they with tiny mistake destroy project
- lib\script.dart


## final goal's and target's I planned for this Project:

** proot container based workspace manager

** containers can be run at same time and using services and notification keeping they running in background

** each container having a manage configurator panel that let user create cron's , services (by using preset form's to user set commands, wrking directory , on fail rules and other service thing ) , some internal value configrator for each container as DNS and PATH , some preset script for setup and uninstall SDK's , App's , runtime libraries. 

** by using an undecided(still final protocol  for use in this role not be choosed) and few tiny go cli app we putting inside each container , we getting realtime status , logs , files and from dart internally getting and using info for creating monitoring and performing tasks

** we have especially container workspace type for running vscode fully .

** we creating a full code editor using just flutter and for most challengable part (LSP servers and after that version manager) running SDK's inside container and by using Code_forge package connecting to LSP servers and using them from flutter space. and for version manage system we used git inside container

** we adding full file explorer for each container inside flutter and by helping tiny go app we deploy to using in workspaces.

** user can any time poweroff or poweron or delete fully from phone storage  each container wanted.


## with above project explain you always know our target .