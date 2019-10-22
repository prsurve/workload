
### $1 is name storageclass that will be used to create pvc
### $2 is pvc count
### eg. sh pvc-create-bulk.sh sc_name 2


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


for index in $(seq 1 $no_of_pvc)
do
	pvc_name=pvc-$(cat /dev/urandom | tr -dc 'a-z' | fold -w 9 | head -n 1)
	printf "\nCreating pvc with name $pvc_name\n"
	create_pvc 
done	
