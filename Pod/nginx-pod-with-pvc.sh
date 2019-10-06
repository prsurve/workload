#!/bin/bash

### $1 is name storageclass that will be used to create pvc
### $2 is No of nginx pods
### eg. sh fedora-create-dc-with-pvc.sh sc_name 2


sc_name=$1
no_of_pods=$2
verify_output ()
{
	if [ $? -eq 0 ]
	then
	  printf "\nCommand Executed successfully"
	else
	  printf "\nCommand Failed:- $OUTPUT" >&2
	fi	
}


create_pvc ()
{
echo "kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $pvc_name
  namespace: $project_name
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 3Gi
  storageClassName: $sc_name" | oc create --recursive=true -f -
}


create_nginx_pod ()
{
echo "---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod-$index
  namespace: $project_name
spec:
  containers:
   - name: web-server
     image: nginx
     volumeMounts:
       - name: mypvc
         mountPath: /var/lib/www/html
  volumes:
   - name: mypvc
     persistentVolumeClaim:
       claimName: $pvc_name
       readOnly: false
" | oc create --recursive=true -f -
}


check_status_pvc ()
{
	for i in {1..20}
	do
		status=$(oc get pvc $pvc_name -n $project_name -o custom-columns=:.status.phase |tr -d '\n' 2>&1)

		if [ $status == "Bound" ]
		then
			printf "PVC got bound successfully\n"
			break
		else
			printf "PVC failed to reach bound State\n"
		fi
		sleep 2
	done
}


project_name=namespace-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
printf "\nCreated new Project with name $project_name" 
OUTPUT=$(oc new-project $project_name 2>&1)

verify_output $OUTPUT


for index in $(seq 1 $no_of_pods)
do
	pvc_name=pvc-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 9 | head -n 1)
	printf "\nCreating pvc with name $pvc_name\n"
	create_pvc 
	check_status_pvc
	printf "\nCreating Pod with name nginx-pod-$index\n"
	create_nginx_pod
done
