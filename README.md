# docker_devops
Script de Docker para desplegar aplicaciones

``` script
passwd
cd /opt
git clone https://github.com/fpempresa/docker_webapps.git
cd ./docker_webapps/bin
./install.sh

```

Y despues de instalar todo deberás para cada aplicación

``` script
./webapp.sh add 
./webapp.sh start_jenkins <nombre_app> <environment>
```
Y desde Jenkins ejecutar 'restore_database' y 'compile_and_deploy' 

