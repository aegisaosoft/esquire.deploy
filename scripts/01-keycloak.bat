@echo off
title Keycloak (port 8080)
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
set KC_BOOTSTRAP_ADMIN_USERNAME=admin
set KC_BOOTSTRAP_ADMIN_PASSWORD=admin
cd /d C:\keycloak-26.0.7
bin\kc.bat start-dev --http-port=8080
