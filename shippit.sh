#!/bin/sh
TIC80=/E/tic80-v1.1-win/tic80 
CART=wandermaze
ITCH=wandermaze

rm -rf ./pub-linux
rm -rf ./pub-windows
rm -rf ./pub-mac
rm -rf ./pub-html
mkdir ./pub-linux
mkdir ./pub-windows
mkdir ./pub-mac
mkdir ./pub-html
$TIC80 --cli --fs=. --cmd "load $CART.tic & export html ./pub-html/$CART.zip & exit" 
$TIC80 --cli --fs=. --cmd "load $CART.tic & export win ./pub-windows/$CART & exit" 
$TIC80 --cli --fs=. --cmd "load $CART.tic & export linux ./pub-linux/$CART & exit" 
$TIC80 --cli --fs=. --cmd "load $CART.tic & export mac ./pub-mac/$CART & exit" 
butler push pub-html/$CART.zip thegrumpygamedev/$ITCH:html
butler push pub-windows thegrumpygamedev/$ITCH:windows
butler push pub-linux thegrumpygamedev/$ITCH:linux
butler push pub-mac thegrumpygamedev/$ITCH:mac
git add -A
git commit -m "shipped it!"