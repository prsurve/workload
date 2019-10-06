
### $1 is name storageclass that will be used to create pvc
### $2 is pvc count
### eg. sh pvc-create-bulk-wait-for-status.sh sc_name 2


sc_name=$1
no_of_pvc=$2

create_pvc ()
{
echo "kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $pvc_name
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 3Gi
  storageClassName: $sc_name" | oc create --recursive=true -f -
}

check_status_pvc ()
{
	for i in {1..20}
	do
		status=$(oc get pvc $pvc_name -o custom-columns=:.status.phase |tr -d '\n' 2>&1)

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


for index in $(seq 1 $no_of_pods)
do
	pvc_name=pvc-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 9 | head -n 1)
	printf "\nCreating pvc with name $pvc_name\n"
	create_pvc 
	check_status_pvc
done	
