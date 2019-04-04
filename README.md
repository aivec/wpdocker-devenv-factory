# Wordpress Docker Container Factory

## Summary
This repository is meant to be an all purpose Wordpress local container generator for setting up development environments. You can define any number of projects you want and launch or stop them all simultaneously or piecemeal. Configurable automated settings include: 
- local plugin/theme volume mounts
- downloading and installing free themes/plugins via wp-cli
- downloading and installing proprietary plugins/themes from an ftp server
- using a MySQL dump file to setup a pre-configured instance (url search-replace included)
- parsing `active_plugins` in the options table to install necessary plugins on a new instance.

This tool also automatically sets up XDebug for PHP, which can be listened to from your host machine in VS Code, for example.   

## Prerequisites
- docker-ce ([Linux](https://docs.docker.com/install/#server), [MacOS](https://docs.docker.com/docker-for-mac/install/), [Windows 10 Pro/Enterprise](https://docs.docker.com/docker-for-windows/install/), [Windows 10 Home](https://download.docker.com/win/stable/DockerToolbox.exe))
- docker-compose ([Linux](https://docs.docker.com/compose/install/#linux), MacOS: included with docker-ce, Windows: included with docker-ce)
- git
- bash
- [jq](https://stedolan.github.io/jq/download/)

## How to use
An example configuration file can be found in `exampleconfigs/wp-instances.json`. It's pretty self-explanatory. A file of the same name must exist in the root of this project. After configuring your instance(s), run the following interactive script to get started:
```sh
$ ./run.sh
```
That's it!
