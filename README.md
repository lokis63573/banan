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
echo nameserver 10.10.100.2 > /etc/net/ifaces/ens3/resolv.conf
echo nameserver 77.88.8.8 > /etc/net/ifaces/ens3/resolv.conf
systemctl restart network
```

# заходим на br-srv
```bash
echo 10.20.20.2/28 > /etc/net/ifaces/ens3/ipv4address 
echo default via 10.20.20.1 > /etc/net/ifaces/ens3/ipv4route   
echo nameserver 10.10.100.2 > /etc/net/ifaces/ens3/resolv.conf
echo nameserver 77.88.8.8 > /etc/net/ifaces/ens3/resolv.conf
systemctl restart network
```
# заходим на br-cli
настраиваем ip адрес
hostnamectl set-hostname br-cli.au-team.irpo
mcedit /etc/sysconfig/network
HOSTNAME=br-cli.au-team.irpo
exec bash
Теперь настроим ospf на br-fw
 <img width="534" height="245" alt="image" src="https://github.com/user-attachments/assets/533105cf-b219-4fbe-be35-452e024d8f43" />
Правой кнопкой мыши

 <img width="525" height="336" alt="image" src="https://github.com/user-attachments/assets/00cb6955-db15-4fe8-84ca-7b0f0b6f247d" />

Заходите на проводное подключение 2 и вырубаете наху

 <img width="974" height="183" alt="image" src="https://github.com/user-attachments/assets/b3d42179-0464-4b16-9365-757f3a8b11b0" />

Не забудьте сохранить (пароль toor)

Дальше заходим на первое подключение и вставляем ip

 <img width="953" height="638" alt="image" src="https://github.com/user-attachments/assets/19d41a2c-d9cc-4aab-890a-113538bbcae1" />
Далее заходим в браузер
 
 <img width="927" height="734" alt="image" src="https://github.com/user-attachments/assets/c7f35c75-51a1-437d-b250-018128e68c0c" />

В строку вбиваете

 <img width="369" height="66" alt="image" src="https://github.com/user-attachments/assets/9ca9e94b-010a-4172-8c8c-15f4017d33c8" />

Вам может сказать, что сайт опасный, но на него всё же надо зайти.
Дальше будет вкладка авторизации. Вам будет выдана бумажка. Нам нужно смотреть в :”Учётные записи ВМ”, Ideco NGFW
Дальше открываете меню и пишите название.

 <img width="453" height="331" alt="image" src="https://github.com/user-attachments/assets/2898079a-7907-40eb-b9f3-d2659108c5a2" />
 <img width="420" height="192" alt="image" src="https://github.com/user-attachments/assets/79ab7674-4945-4bd1-bf6d-115f1b7f7cf3" />

Дальше в том же меню ищите «маршрутизация» >>  «ospf»
Делаете как я 

 <img width="760" height="672" alt="image" src="https://github.com/user-attachments/assets/c44c3cfa-94c9-4145-8ecf-51653c9f2d2b" />
 <img width="497" height="238" alt="image" src="https://github.com/user-attachments/assets/3ef72c80-6485-42dc-9a78-b6578d7799d3" />

 


