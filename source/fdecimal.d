module fdecimal;

import BigFixed;

alias fdecimal = double;

// int pow
fdecimal ipow(fdecimal num, int power) {
  fdecimal res = 1;

  if (!power) return res;

  bool positive = power > 0;

  if (power < 0) {
    power *= -1;
  }

  for (int i = 0; i < power; i++) {
    res *= num;
  }

  return positive ? res : 1/res;
}

// pow

// cos 

// sin 

// atan2

// cast

// log (return real)