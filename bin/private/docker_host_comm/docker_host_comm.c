#include <stdio.h> 
#include <string.h> 
#include <fcntl.h> 
#include <sys/stat.h> 
#include <sys/types.h> 
#include <unistd.h> 
#include <stdlib.h>

int main(int argc, char *argv[]) 
{ 
	char line[8000];
	char pipePath[4096];
	char execLine[4096];
	char cwd[4096];
  	char* basePath;

	if (argc != 2) {
		fprintf(stderr, "Usage: %s <base_path>\n", argv[0]);
		return 1;
  	}

	basePath = argv[1]; 

	chdir(basePath);

	if (getcwd(cwd, sizeof(cwd)) != NULL) {
		printf("Directorio actual:%s\n", cwd);
	} else {
		fprintf(stderr,"getcwd() error");
		return 1;
	} 

	strcpy(pipePath,cwd);
	strcat(pipePath,"/var/pipe_send_to_server_command");
	printf("pipePath:%s\n", pipePath);
	

	FILE* file = fopen(pipePath, "r");

	if (file == NULL) {
		fprintf(stderr, "No existe el PIPE\n");
		return 1;
	}
 	while (1) {
		char* returnLine=fgets(line,sizeof(line), file);

		if (returnLine==NULL) {
			fclose(file); 
			file = fopen(pipePath, "r");
		} else {
			printf("%s",line); 
			/* system("git pull"); */
			sprintf(execLine,"/bin/bash -c '%s/bin/private/docker_host_comm/exec_command.sh %s' &",cwd,line); 
			system(execLine);

			
    	}

	}

	fclose(file); 
	return 1; 
} 


