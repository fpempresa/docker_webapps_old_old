#include <stdio.h> 
#include <string.h> 
#include <fcntl.h> 
#include <sys/stat.h> 
#include <sys/types.h> 
#include <unistd.h> 
  
int main(int argc, char *argv[]) 
{ 





	char line[50000];

	if (argc != 3) {
		fprintf(stderr, "Usage: %s <pipePath> <endString>\n", argv[0]);
		return 1;
	}

	char * pipePath = argv[1]; 

	FILE* file = fopen(pipePath, "r");
	int salir=0;
	while (salir==0) {
		if (fgets(line,sizeof(line), file)) {
			printf("%s", line); 
			if (prefix(argv[2],line)) {
				salir=1;

				char * pch = strtok (line," ");
				pch = strtok (NULL, " ");
				pch = strtok (NULL, " ");
				fclose(file); 
				return atoi(pch);
			}
		} else {
			fclose(file); 
			file = fopen(pipePath, "r");
		}

	}



	fclose(file); 



	return 0; 
} 

int prefix(const char *pre, const char *str)
{
    return strncmp(pre, str, strlen(pre)) == 0;
}
