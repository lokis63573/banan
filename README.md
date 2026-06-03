# banan
# это демо syчки, мы сделаем все что бы было хорошо
_____________________________________________________________________________________________________________________________________________________________________________________

На случай не правильного написания ip
( не правильного вбивания ip)
```
rm /etc/net/ifaces/ens3/*имя файлы
```
После того как он спросит удалить написать 

```
yes
```



# заходим на isp и пишем


```
curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/isp.sh -o /root/isp.sh
chmod +x /root/isp.sh
bash /root/isp.sh
```
# заходим на hq-srv
```
echo 10.10.100.2/27 > /etc/net/ifaces/ens3/ipv4address 
echo default via 10.10.100.1 > /etc/net/ifaces/ens3/ipv4route   
echo nameserver 10.10.100.2 > /etc/net/ifaces/ens3/resolv.conf
echo nameserver 77.88.8.8 > /etc/net/ifaces/ens3/resolv.conf
systemctl restart network
```
проверьте что все правильно
```
ping 10.10.100.1
```
# заходим на br-srv
```
echo 10.20.20.2/28 > /etc/net/ifaces/ens3/ipv4address 
echo default via 10.20.20.1 > /etc/net/ifaces/ens3/ipv4route   
echo nameserver 10.10.100.2 > /etc/net/ifaces/ens3/resolv.conf
echo nameserver 77.88.8.8 > /etc/net/ifaces/ens3/resolv.conf
systemctl restart network
```

проверьте что все правильно
```
ping 10.20.20.1
```

# заходим на br-cli
настраиваем ip адрес
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
 <img width="835" height="675" alt="image" src="https://github.com/user-attachments/assets/a16793f6-b538-4d7c-8dc5-17b5be5cdbae" />

 Далее проверяем!!!
 <img width="933" height="645" alt="image" src="https://github.com/user-attachments/assets/991cda32-4d48-4206-ab35-22f97359497a" />
 <img width="974" height="276" alt="image" src="https://github.com/user-attachments/assets/e66cea07-a149-4c7b-a803-f43d358f275f" />

# заходим на hq-srv
```
 curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/hq-srv.sh -o /root/hq-srv.sh
chmod +x /root/hq-srv.sh
bash /root/hq-srv.sh
```
 # 2 МОДУЛЬ!!!!!!!!!!!!!!!!!!!!!!!
______________________________________________________________________________________________________________________________________________________

# На isp прописываем вот это:
```
curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m2/isp.sh -o /root/isp.sh
chmod +x /root/isp.sh
bash /root/isp.sh
```

# Заходим на br-srv
```
curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m2/br-srv.sh -o /root/br-srv.sh
chmod +x /root/br-srv.sh
bash /root/br-srv.sh
```
если не работает 1 команда на скачивание то заходим в 
```
mcedit /etc/net/ifaces/ens3/resolv.conf 
```
и дописываем:
```
nameserver 77.88.8.8
```
после чего 
```
systemctl restart network
```

Далее заходим на клиента, заходим в браузер вбиваем 

```
http://web.au-team.irpo
```
логи
```
WEB
```
пароль
```
P@ssw0rd
```
и проверяем что видим именно эту картину

<img width="772" height="551" alt="image" src="https://github.com/user-attachments/assets/7606d7b2-bf9a-4e8b-9f79-76dc5b824529" />

откройте консоль на hq-cli
 поптайтесь войти bruser1 P@ssw0rd1
 он не должен дать этого сделать,
 после чего входите под hquser1 P@ssw0rd1
 задайте вопрос экспертам, в консоли не даёт, а в графике даёт зайти, это будет считаться как выполнение задания?
 <img width="313" height="198" alt="image" src="https://github.com/user-attachments/assets/80b22dd7-fc9b-4ce4-992a-de9e7250cfe7" />

 
 # 3 МОДУЛЬ!!!!!!!!!!!!!!!!!!!!!!!
______________________________________________________________________________________________________________________________________________________

№Вариант 1 (выполняет задание 1+2)
```
curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m3/m3-master.sh -o /root/m3-master.sh
chmod +x /root/m3-master.sh
bash /root/m3-master.sh
```

№Вариант 2(тестовый билд выполнения 1+2+5+6+8+9) 
на свой страх и риск!!!

```
curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m3/chek.sh -o /root/chek.sh
chmod +x /root/chek.sh
bash /root/chek.sh
```
