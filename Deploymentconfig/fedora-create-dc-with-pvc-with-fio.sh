#!/bin/bash

### $1 is name storageclass that will be used to create pvc
### $2 is No of dc pods
### eg. sh fedora-create-dc-with-pvc-with-fio.sh sc_name 2


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
      storage: 5Gi
  storageClassName: $sc_name" | oc create --recursive=true -f -
}


create_fedora_pod ()
{
echo "kind: DeploymentConfig
apiVersion: apps.openshift.io/v1
metadata:
  name: fedorapod-$index
  labels:
    app: fedorapod-$index
spec:
  template:
    metadata:
      labels:
        name: fedorapod-$index
    spec:
      serviceAccountName: $service_account
      restartPolicy: Always
      volumes:
      - name: fedora-vol
        persistentVolumeClaim:
          claimName: $pvc_name
      containers:
      - name: fedora
        image: fedora
        command: ['/bin/bash', '-ce', 'tail -f /dev/null']
        imagePullPolicy: IfNotPresent
        securityContext:
          capabilities: {}
          privileged: true
        volumeMounts:
        - mountPath: /mnt
          name: fedora-vol
        livenessProbe:
          exec:
            command:
            - 'sh'
            - '-ec'
            - 'df /mnt'
          initialDelaySeconds: 3
          periodSeconds: 3

  replicas: 1
  triggers:
    - type: ConfigChange
  paused: false" | oc create --recursive=true -f -
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

check_pod_status ()
{
	for index in $(seq 1 $no_of_pods)
	do
		for cnt in {1..30}
		do	
			status=$(oc get pod --selector=name=fedorapod-$index -o custom-columns=:.status.phase |tr -d '\n')

			if [[ $status == "Running" ]]
			then
				printf "\n\nPod fedorapod-$index reached Running State\n\n"
				break
			else				
				COUNT=$(expr 60 - $cnt)
				printf "Retry left $COUNT..."
				printf "Retrying After 5 sec..\n"
				if [ $COUNT == "0" ]
				then
					printf "Pod fedorapod-$index Failed to reached Running State\n"
				fi				
			fi
			sleep 5
		done
		
	done
}

run_fio ()
{
	for pod_name in $(oc get po --no-headers |grep -v "deploy" |grep "Running" |awk '{print$1}')
	do
		OUTPUT=$(oc cp run-fio.sh $pod_name:/mnt/)
		verify_output $OUTPUT
	done
	for pod_name in $(oc get po --no-headers |grep -v "deploy" |grep "Running" |awk '{print$1}')
        do
		OUTPUT=$(oc rsh $pod_name sh /mnt/run-fio.sh &)
		verify_output $OUTPUT
        done

}

project_name=namespace-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
printf "\nCreated new Project with name $project_name" 
OUTPUT=$(oc new-project $project_name 2>&1)

verify_output $OUTPUT
service_account=sa-name-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
printf "\nCreating serviceaccount with name $service_account"
OUTPUT=$(oc create serviceaccount $service_account -n $project_name 2>&1)

verify_output $OUTPUT

printf "\nAdding Serviceaccount to SCC/privileged"

OUTPUT=$(oc adm policy add-scc-to-user privileged system:serviceaccount:$project_name:$service_account 2>&1)

verify_output $OUTPUT


for index in $(seq 1 $no_of_pods)
do
	pvc_name=pvc-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 9 | head -n 1)
	printf "\nCreating pvc with name $pvc_name\n"
	create_pvc 
	check_status_pvc
	printf "\nCreating Pod with name fedorapod-$index\n"
	create_fedora_pod
done	

printf "\nChecking Status of pod\n"
check_pod_status
printf "\n Running Fio script"
run_fio
