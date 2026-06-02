# banan
# это демо syчки, мы сделаем все что бы было хорошо
_____________________________________________________________________________________________________________________________________________________________________________________
# заходим на isp и пишем
```text
https://github.com/lokis63573/banan
```

```bash
curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/isp.sh -o /root/isp.sh
chmod +x /root/isp.sh
bash /root/isp.sh
```
# заходим на hq-srv
```bash
echo 10.10.100.2/27 > /etc/net/ifaces/ens3/ipv4address 
echo default via 10.10.100.1 > /etc/net/ifaces/ens3/ipv4route   
echo nameserver 10.10.100.2 77.88.8.8 > /etc/net/ifaces/ens3/resolv.conf
systemctl restart network
```
