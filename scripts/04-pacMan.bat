@echo off
title PacMan (port 3004)
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
"%JAVA_HOME%\bin\java" -DPACMAN_PORT=3004 -DDB_PACMAN_VENDOR=dev-postgres -DDB_PACMAN_HOST=192.168.1.104 -DDB_PACMAN_PORT=5432 -DDB_PACMAN_NAME=esq2025 -DDB_PACMAN_USERNAME=esq2025 -DDB_PACMAN_PASSWORD=q -DLOG_LEVEL_ROOT=ERROR -DLOG_LEVEL_MIR0N=DEBUG -jar C:\aegis-miron\esquire.services\pacMan\target\esquire-pac-man.jar
pause
