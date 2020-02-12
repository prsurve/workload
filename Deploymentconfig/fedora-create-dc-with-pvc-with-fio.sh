#!/bin/bash

### $1 is name storageclass that will be used to create pvc
### $2 is No of dc pods
### eg. sh fedora-create-dc-with-pvc-with-fio.sh -sc sc_name -c 2 -p project_name -m rwx,rwo
### project_name is optional
### -m is optional 

function show_usage (){
    printf "Usage: $0 [options [parameters]]\n"
    printf "\n"
    printf "Options:\n"
    printf " -sc|--storage_class, Storageclass name\n"
    printf " -c|--count, Count of required Pod\n"
    printf " -p|--project_name, Project Name|Namespace\n"
    printf " -m|--mode, PVC mode (RWX,RWO) \n"
    printf " -h|--help, Print help\n"

return 0
}

while [ ! -z "$1" ]; do
  case "$1" in
     -sc|--storage_class)
         shift
         echo "Using storage class: $1	"
         sc_name=$1
         ;;
     -c|--count)
         shift
         no_of_pods=$1
         if ! [[ "$no_of_pods" =~ ^[0-9]+$ ]]
    	then
        	printf "Required Integer value\n"
        	exit 1
		fi
         echo "Pods to create: $1"         
         ;;
     -p|--project_name)
        shift	
        echo "Creating pod in  : $1"
        project_name=$1
         ;;
     -m|--mode)
        shift
		pvc_mode=$(echo "$1" | awk '{print tolower($0)}')
		if [[ $pvc_mode = "rwo" ]]
		then
			pvc_type[0]="ReadWriteOnce"
			printf "Using $pvc_type mode for pvc creation\n"
		elif [[ $pvc_mode = "rwx" ]]
		then
			pvc_type[0]="ReadWriteMany"
			printf "Using $pvc_type mode for pvc creation\n"
		elif [[ $pvc_mode = "any" ]]
		then
			pvc_type[0]="ReadWriteMany"
			pvc_type[1]="ReadWriteOnce"
			printf "Using RWX,RWO mode for pvc creation\n"
		else
			printf "Entered mode not supported or it's invalid\n"
			printf "Valid Modes are RWX, RWO\n"
			exit 1
		fi
         ;;	 
     *)
        show_usage
        exit 1
        ;;
  esac
shift
done


if [ -z "$sc_name" ]
then
	printf "You need to pass storageclass Name\n"
	exit 1
fi
if [ -z "$no_of_pods" ]
then
      printf "You need to pass No of required Pod\n"
      exit 1
fi
verify_output ()
{
	if [ $? -eq 0 ]
	then
	  printf "\nCommand Executed successfully"
	else
	  printf "\nCommand Failed:- $OUTPUT\n" >&2
	  exit 1
	fi	
}

if [ -z "$pvc_mode" ]
then
	pvc_type[0]="ReadWriteMany"
	pvc_type[1]="ReadWriteOnce"
fi
mount_type[0]="volumeMounts:
        - mountPath: /mnt
          name: fedora-vol"
mount_type[1]="volumeDevices:
        - devicePath: /dev/rbdblock
          name: fedora-vol"
create_pvc ()
{
echo "kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $pvc_name
  namespace: $project_name
spec:
  accessModes:
    - $selected_mode
  $if_block_mode
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
  name: ${FEDORA_POD_LIST[$index]}
  namespace: $project_name
  labels:
    app: ${FEDORA_POD_LIST[$index]}
spec:
  template:
    metadata:
      labels:
        name: ${FEDORA_POD_LIST[$index]}
    spec:
      securityContext:
        fsGroup: 2000
      serviceAccountName: $service_account
      restartPolicy: Always
      volumes:
      - name: fedora-vol
        persistentVolumeClaim:
          claimName: $pvc_name
      containers:
      - name: fedora
        image: prsurve/fedora_fio
        resources:
            limits:
                memory: "800Mi"
                cpu: "150m"  
        command: ['/bin/bash', '-ce', 'tail -f /dev/null']
        imagePullPolicy: IfNotPresent
        $selected_mount_mode
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
	for index in "${FEDORA_POD_LIST[@]}"
	do
		for cnt in {1..30}
		do	
			status=$(oc get pod -n $project_name --selector=name=$index -o custom-columns=:.status.phase |tr -d '\n')

			if [[ $status == "Running" ]]
			then
				printf "\n\nPod $index reached Running State\n\n"
				break
			else				
				COUNT=$(expr 60 - $cnt)
				printf "Retry left $COUNT..."
				printf "Retrying After 5 sec..\n"
				if [ $COUNT == "0" ]
				then
					printf "Pod $index Failed to reached Running State\n"
				fi				
			fi
			sleep 5
		done
		
	done
}

run_fio ()
{
	for index in "${FEDORA_POD_LIST[@]}"
	do
		pod_name=$(oc get pod -n $project_name --selector=name=$index -o custom-columns=:.metadata.name |tr -d '\n')
		printf "\n Coping script on pod $pod_name"
		tmp_pod_interface=$(printf $pod_name|cut -d "-" -f2)
		tmp_pod_mode=$(printf $pod_name|cut -d "-" -f3)
				if [[ $tmp_pod_interface == "rbd" ]]
				then
					if [[ $tmp_pod_mode == "rwx" ]]
					then
						OUTPUT=$(oc cp run-fio-rwx.sh $project_name/$pod_name:/mnt/)
					else
						OUTPUT=$(oc cp run-fio.sh $project_name/$pod_name:/mnt/)
					fi
				else
                	OUTPUT=$(oc cp run-fio.sh $project_name/$pod_name:/mnt/)
                fi
                verify_output $OUTPUT
	done
	for index in "${FEDORA_POD_LIST[@]}"
        do
		pod_name=$(oc get pod -n $project_name --selector=name=$index -o custom-columns=:.metadata.name |tr -d '\n') 
		tmp_pod_interface=$(printf $pod_name|cut -d "-" -f2)
		tmp_pod_mode=$(printf $pod_name|cut -d "-" -f3)
				if [[ $tmp_pod_interface == "rbd" ]]
				then
					if [[ $tmp_pod_mode == "rwx" ]]
					then
						OUTPUT=$(oc -n $project_name rsh $pod_name sh /mnt/run-fio-rwx.sh &) &
					else
						OUTPUT=$(oc -n $project_name rsh $pod_name sh /mnt/run-fio.sh &) &
					fi
				else
                	OUTPUT=$(oc -n $project_name rsh $pod_name sh /mnt/run-fio.sh &) &
                fi
        done

}

if [ -z "$project_name" ]
then
	project_name=namespace-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
	printf "\nCreated new Project with name $project_name" 
	OUTPUT=$(oc new-project $project_name 2>&1)
	verify_output $OUTPUT
else
	printf "\nUsing $project_name for creation"
fi

service_account=sa-name-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 4 | head -n 1)
printf "\nCreating serviceaccount with name $service_account"
OUTPUT=$(oc create serviceaccount $service_account -n $project_name 2>&1)

verify_output $OUTPUT

printf "\nAdding Serviceaccount to SCC/privileged"

OUTPUT=$(oc adm policy add-scc-to-user privileged system:serviceaccount:$project_name:$service_account 2>&1)

verify_output $OUTPUT

provisioner=$(oc get sc $sc_name -o custom-columns=:.provisioner|tr -d '\n'|cut -d '.' -f2 2>&1)
if [[ $provisioner == "cephfs" ]]
then

	selected_mount_mode=${mount_type[0]}
fi
for index in $(seq 1 $no_of_pods)
do
	selected_mode=${pvc_type[$RANDOM % ${#pvc_type[@]} ]}
	if [[ $selected_mode == "ReadWriteOnce" ]]
	then
		mode="rwo"
	elif [[ $selected_mode == "ReadWriteMany" ]]
	then
		mode="rwx"
	fi
	if [[ $provisioner == "rbd" ]]
	then
		if [[ $mode == "rwx" ]]
		then
			if_block_mode="volumeMode: Block"
			selected_mount_mode=${mount_type[1]}
		else
			selected_mount_mode=${mount_type[0]}
		fi
	fi	
	pvc_name=pvc-$provisioner-$mode-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 9 | head -n 1)
	
	printf "\nCreating pvc with name $pvc_name and accessModes is $mode \n"
	create_pvc 
	check_status_pvc
	
	FEDORA_POD_LIST[$index]=fedorapod-$provisioner-$mode-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 5 | head -n 1)
	printf "\nCreating Pod with name ${FEDORA_POD_LIST[$index]}\n"
	create_fedora_pod
	unset if_block_mode
done

printf "\nChecking Status of pod\n"
check_pod_status $FEDORA_POD_LIST
printf "\n Running Fio script"
run_fio
