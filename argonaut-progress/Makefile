all:
	moc kprogress.h -o kprogress.moc
	gcc -c -I /usr/include/qt3 -o kprogress.o kprogress.cpp
	gcc -c -I /usr/include/qt3 -o main.o main.cpp
	gcc -lqt-mt main.o kprogress.o -o kprogress
	strip kprogress

