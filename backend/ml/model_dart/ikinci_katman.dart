/// ANN ikinci katman onayi (Asama 7.6) - OTOMATIK URETILDI, elle DUZENLEMEYIN.
/// Kaynak: ml/scripts/09_dart_disa_aktar.py -> RandomForestClassifier(15 agac,
/// derinlik 5) -> 15 agacin if/else karsiligi.
///
/// Ozellik sirasi (f listesi): ['sta_lta_orani', 'log_enerji', 'sifir_gecis_orani', 'bant_enerji_orani']
/// _sarsintiKontrolEt (Aşama 3) "supheli" dedikten SONRA cagrilacak ikinci onay katmani.
library;

/// 15 agacin pozitif-sinif olasiliklarinin ORTALAMASINI dondurur
/// (0.0-1.0 arasi) - RandomForestClassifier.predict_proba ile AYNI mantik.
double ikinciKatmanOlasilik(List<double> f) {
  double toplam = 0.0;
  toplam += _agac0(f);
  toplam += _agac1(f);
  toplam += _agac2(f);
  toplam += _agac3(f);
  toplam += _agac4(f);
  toplam += _agac5(f);
  toplam += _agac6(f);
  toplam += _agac7(f);
  toplam += _agac8(f);
  toplam += _agac9(f);
  toplam += _agac10(f);
  toplam += _agac11(f);
  toplam += _agac12(f);
  toplam += _agac13(f);
  toplam += _agac14(f);
  return toplam / 15;
}

/// 0.5 esigiyle ikili karar (RandomForestClassifier.predict ile AYNI esik).
bool ikinciKatmanOnayVer(List<double> f) => ikinciKatmanOlasilik(f) >= 0.5;

double _agac0(List<double> f) {
  // log_enerji <= -1.160642 ?
  if (f[1] <= -1.160642) {
    // bant_enerji_orani <= 0.048479 ?
    if (f[3] <= 0.048479) {
      // sifir_gecis_orani <= 0.390000 ?
      if (f[2] <= 0.390000) {
        // bant_enerji_orani <= 0.048453 ?
        if (f[3] <= 0.048453) {
          // log_enerji <= -1.450022 ?
          if (f[1] <= -1.450022) {
            return 0.007859;
          } else {
            return 0.292683;
          }
        } else {
          return 1.000000;
        }
      } else {
        // sifir_gecis_orani <= 0.410000 ?
        if (f[2] <= 0.410000) {
          // sta_lta_orani <= 1.833053 ?
          if (f[0] <= 1.833053) {
            return 1.000000;
          } else {
            return 0.000000;
          }
        } else {
          return 1.000000;
        }
      }
    } else {
      // sifir_gecis_orani <= 0.410000 ?
      if (f[2] <= 0.410000) {
        // log_enerji <= -1.369737 ?
        if (f[1] <= -1.369737) {
          // sta_lta_orani <= 0.362379 ?
          if (f[0] <= 0.362379) {
            return 0.010115;
          } else {
            return 0.002112;
          }
        } else {
          // bant_enerji_orani <= 0.094492 ?
          if (f[3] <= 0.094492) {
            return 0.264583;
          } else {
            return 0.096037;
          }
        }
      } else {
        // log_enerji <= -2.133828 ?
        if (f[1] <= -2.133828) {
          return 0.000000;
        } else {
          return 1.000000;
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sifir_gecis_orani <= 0.130000 ?
      if (f[2] <= 0.130000) {
        // sta_lta_orani <= 1.376199 ?
        if (f[0] <= 1.376199) {
          // bant_enerji_orani <= 0.050353 ?
          if (f[3] <= 0.050353) {
            return 0.534722;
          } else {
            return 0.284408;
          }
        } else {
          // sifir_gecis_orani <= 0.030000 ?
          if (f[2] <= 0.030000) {
            return 0.243243;
          } else {
            return 0.782470;
          }
        }
      } else {
        // bant_enerji_orani <= 0.086491 ?
        if (f[3] <= 0.086491) {
          // sifir_gecis_orani <= 0.170000 ?
          if (f[2] <= 0.170000) {
            return 0.645079;
          } else {
            return 0.763827;
          }
        } else {
          // sta_lta_orani <= 1.505919 ?
          if (f[0] <= 1.505919) {
            return 0.337257;
          } else {
            return 0.816612;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.078433 ?
      if (f[3] <= 0.078433) {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // bant_enerji_orani <= 0.014559 ?
          if (f[3] <= 0.014559) {
            return 0.321429;
          } else {
            return 0.914293;
          }
        } else {
          // log_enerji <= -1.000012 ?
          if (f[1] <= -1.000012) {
            return 0.828125;
          } else {
            return 0.995141;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.270000 ?
        if (f[2] <= 0.270000) {
          // sta_lta_orani <= 1.316638 ?
          if (f[0] <= 1.316638) {
            return 0.549176;
          } else {
            return 0.909144;
          }
        } else {
          // sta_lta_orani <= 1.225343 ?
          if (f[0] <= 1.225343) {
            return 0.872365;
          } else {
            return 0.966102;
          }
        }
      }
    }
  }
}

double _agac1(List<double> f) {
  // sifir_gecis_orani <= 0.290000 ?
  if (f[2] <= 0.290000) {
    // bant_enerji_orani <= 0.071530 ?
    if (f[3] <= 0.071530) {
      // sta_lta_orani <= 1.312836 ?
      if (f[0] <= 1.312836) {
        // bant_enerji_orani <= 0.049196 ?
        if (f[3] <= 0.049196) {
          // sifir_gecis_orani <= 0.230000 ?
          if (f[2] <= 0.230000) {
            return 0.443911;
          } else {
            return 0.655990;
          }
        } else {
          // sta_lta_orani <= 0.183819 ?
          if (f[0] <= 0.183819) {
            return 0.194744;
          } else {
            return 0.374716;
          }
        }
      } else {
        // log_enerji <= -0.453905 ?
        if (f[1] <= -0.453905) {
          // sta_lta_orani <= 3.358849 ?
          if (f[0] <= 3.358849) {
            return 0.265449;
          } else {
            return 0.068571;
          }
        } else {
          // sifir_gecis_orani <= 0.030000 ?
          if (f[2] <= 0.030000) {
            return 0.511364;
          } else {
            return 0.965653;
          }
        }
      }
    } else {
      // log_enerji <= -1.006550 ?
      if (f[1] <= -1.006550) {
        // sta_lta_orani <= 0.686850 ?
        if (f[0] <= 0.686850) {
          // log_enerji <= -1.185016 ?
          if (f[1] <= -1.185016) {
            return 0.012432;
          } else {
            return 0.551546;
          }
        } else {
          // log_enerji <= -1.107787 ?
          if (f[1] <= -1.107787) {
            return 0.003017;
          } else {
            return 0.058394;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.170000 ?
        if (f[2] <= 0.170000) {
          // sifir_gecis_orani <= 0.130000 ?
          if (f[2] <= 0.130000) {
            return 0.378073;
          } else {
            return 0.523315;
          }
        } else {
          // sta_lta_orani <= 1.407757 ?
          if (f[0] <= 1.407757) {
            return 0.499099;
          } else {
            return 0.926984;
          }
        }
      }
    }
  } else {
    // sta_lta_orani <= 0.182681 ?
    if (f[0] <= 0.182681) {
      // log_enerji <= -1.576260 ?
      if (f[1] <= -1.576260) {
        // sta_lta_orani <= 0.083922 ?
        if (f[0] <= 0.083922) {
          // sta_lta_orani <= 0.083051 ?
          if (f[0] <= 0.083051) {
            return 0.006873;
          } else {
            return 1.000000;
          }
        } else {
          return 0.000000;
        }
      } else {
        // sta_lta_orani <= 0.024370 ?
        if (f[0] <= 0.024370) {
          // log_enerji <= -1.170250 ?
          if (f[1] <= -1.170250) {
            return 0.000000;
          } else {
            return 1.000000;
          }
        } else {
          // bant_enerji_orani <= 0.074725 ?
          if (f[3] <= 0.074725) {
            return 1.000000;
          } else {
            return 0.946429;
          }
        }
      }
    } else {
      // sifir_gecis_orani <= 0.330000 ?
      if (f[2] <= 0.330000) {
        // sta_lta_orani <= 0.912318 ?
        if (f[0] <= 0.912318) {
          // log_enerji <= -1.214643 ?
          if (f[1] <= -1.214643) {
            return 0.023295;
          } else {
            return 0.974952;
          }
        } else {
          // bant_enerji_orani <= 0.099161 ?
          if (f[3] <= 0.099161) {
            return 0.949640;
          } else {
            return 0.805921;
          }
        }
      } else {
        // bant_enerji_orani <= 0.064579 ?
        if (f[3] <= 0.064579) {
          // log_enerji <= -1.576285 ?
          if (f[1] <= -1.576285) {
            return 0.025641;
          } else {
            return 1.000000;
          }
        } else {
          // sifir_gecis_orani <= 0.370000 ?
          if (f[2] <= 0.370000) {
            return 0.791277;
          } else {
            return 0.966631;
          }
        }
      }
    }
  }
}

double _agac2(List<double> f) {
  // sta_lta_orani <= 1.374604 ?
  if (f[0] <= 1.374604) {
    // log_enerji <= -1.217206 ?
    if (f[1] <= -1.217206) {
      // log_enerji <= -1.447969 ?
      if (f[1] <= -1.447969) {
        // sifir_gecis_orani <= 0.430000 ?
        if (f[2] <= 0.430000) {
          // sta_lta_orani <= 0.015666 ?
          if (f[0] <= 0.015666) {
            return 0.030108;
          } else {
            return 0.004849;
          }
        } else {
          return 1.000000;
        }
      } else {
        // bant_enerji_orani <= 0.071372 ?
        if (f[3] <= 0.071372) {
          // sta_lta_orani <= 0.202764 ?
          if (f[0] <= 0.202764) {
            return 0.861111;
          } else {
            return 0.246479;
          }
        } else {
          // sta_lta_orani <= 0.200827 ?
          if (f[0] <= 0.200827) {
            return 0.425287;
          } else {
            return 0.052786;
          }
        }
      }
    } else {
      // log_enerji <= 0.694463 ?
      if (f[1] <= 0.694463) {
        // sifir_gecis_orani <= 0.110000 ?
        if (f[2] <= 0.110000) {
          // log_enerji <= -0.849624 ?
          if (f[1] <= -0.849624) {
            return 0.434368;
          } else {
            return 0.796396;
          }
        } else {
          // log_enerji <= -0.855510 ?
          if (f[1] <= -0.855510) {
            return 0.661074;
          } else {
            return 0.966301;
          }
        }
      } else {
        // sta_lta_orani <= 0.681550 ?
        if (f[0] <= 0.681550) {
          // bant_enerji_orani <= 0.093959 ?
          if (f[3] <= 0.093959) {
            return 0.886547;
          } else {
            return 0.445312;
          }
        } else {
          // log_enerji <= 1.511679 ?
          if (f[1] <= 1.511679) {
            return 0.160289;
          } else {
            return 0.877928;
          }
        }
      }
    }
  } else {
    // log_enerji <= -0.424000 ?
    if (f[1] <= -0.424000) {
      // log_enerji <= -0.873415 ?
      if (f[1] <= -0.873415) {
        // bant_enerji_orani <= 0.052144 ?
        if (f[3] <= 0.052144) {
          // sifir_gecis_orani <= 0.330000 ?
          if (f[2] <= 0.330000) {
            return 0.061798;
          } else {
            return 0.875000;
          }
        } else {
          // log_enerji <= -0.939532 ?
          if (f[1] <= -0.939532) {
            return 0.003143;
          } else {
            return 0.067568;
          }
        }
      } else {
        // bant_enerji_orani <= 0.109985 ?
        if (f[3] <= 0.109985) {
          // sifir_gecis_orani <= 0.250000 ?
          if (f[2] <= 0.250000) {
            return 0.391975;
          } else {
            return 0.823529;
          }
        } else {
          // sifir_gecis_orani <= 0.290000 ?
          if (f[2] <= 0.290000) {
            return 0.046122;
          } else {
            return 0.500000;
          }
        }
      }
    } else {
      // log_enerji <= -0.017009 ?
      if (f[1] <= -0.017009) {
        // sta_lta_orani <= 3.158216 ?
        if (f[0] <= 3.158216) {
          // sifir_gecis_orani <= 0.110000 ?
          if (f[2] <= 0.110000) {
            return 0.781395;
          } else {
            return 0.966618;
          }
        } else {
          // bant_enerji_orani <= 0.084762 ?
          if (f[3] <= 0.084762) {
            return 0.817391;
          } else {
            return 0.201238;
          }
        }
      } else {
        // sta_lta_orani <= 1.537145 ?
        if (f[0] <= 1.537145) {
          // log_enerji <= 1.008712 ?
          if (f[1] <= 1.008712) {
            return 0.960578;
          } else {
            return 0.589577;
          }
        } else {
          // sifir_gecis_orani <= 0.030000 ?
          if (f[2] <= 0.030000) {
            return 0.359756;
          } else {
            return 0.979355;
          }
        }
      }
    }
  }
}

double _agac3(List<double> f) {
  // log_enerji <= -1.013311 ?
  if (f[1] <= -1.013311) {
    // log_enerji <= -1.371367 ?
    if (f[1] <= -1.371367) {
      // sifir_gecis_orani <= 0.410000 ?
      if (f[2] <= 0.410000) {
        // sifir_gecis_orani <= 0.390000 ?
        if (f[2] <= 0.390000) {
          // log_enerji <= -1.537354 ?
          if (f[1] <= -1.537354) {
            return 0.003881;
          } else {
            return 0.077435;
          }
        } else {
          // log_enerji <= -1.710918 ?
          if (f[1] <= -1.710918) {
            return 0.000000;
          } else {
            return 1.000000;
          }
        }
      } else {
        // bant_enerji_orani <= 0.056012 ?
        if (f[3] <= 0.056012) {
          return 1.000000;
        } else {
          // sta_lta_orani <= 0.301964 ?
          if (f[0] <= 0.301964) {
            return 1.000000;
          } else {
            return 0.142857;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.076454 ?
      if (f[3] <= 0.076454) {
        // sta_lta_orani <= 0.868022 ?
        if (f[0] <= 0.868022) {
          // sifir_gecis_orani <= 0.290000 ?
          if (f[2] <= 0.290000) {
            return 0.591731;
          } else {
            return 0.963964;
          }
        } else {
          // sta_lta_orani <= 1.484610 ?
          if (f[0] <= 1.484610) {
            return 0.309392;
          } else {
            return 0.010638;
          }
        }
      } else {
        // sta_lta_orani <= 0.241044 ?
        if (f[0] <= 0.241044) {
          // sifir_gecis_orani <= 0.110000 ?
          if (f[2] <= 0.110000) {
            return 0.439024;
          } else {
            return 0.890110;
          }
        } else {
          // sifir_gecis_orani <= 0.330000 ?
          if (f[2] <= 0.330000) {
            return 0.063598;
          } else {
            return 1.000000;
          }
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sta_lta_orani <= 1.376768 ?
      if (f[0] <= 1.376768) {
        // sta_lta_orani <= 0.681550 ?
        if (f[0] <= 0.681550) {
          // sta_lta_orani <= 0.571345 ?
          if (f[0] <= 0.571345) {
            return 0.907651;
          } else {
            return 0.667954;
          }
        } else {
          // log_enerji <= 0.677409 ?
          if (f[1] <= 0.677409) {
            return 0.837978;
          } else {
            return 0.124338;
          }
        }
      } else {
        // log_enerji <= -0.297997 ?
        if (f[1] <= -0.297997) {
          // log_enerji <= -0.509797 ?
          if (f[1] <= -0.509797) {
            return 0.136879;
          } else {
            return 0.494432;
          }
        } else {
          // sta_lta_orani <= 1.536484 ?
          if (f[0] <= 1.536484) {
            return 0.683860;
          } else {
            return 0.944429;
          }
        }
      }
    } else {
      // sifir_gecis_orani <= 0.250000 ?
      if (f[2] <= 0.250000) {
        // sta_lta_orani <= 1.396649 ?
        if (f[0] <= 1.396649) {
          // log_enerji <= 0.783660 ?
          if (f[1] <= 0.783660) {
            return 0.965226;
          } else {
            return 0.411343;
          }
        } else {
          // log_enerji <= -0.358238 ?
          if (f[1] <= -0.358238) {
            return 0.373563;
          } else {
            return 0.985289;
          }
        }
      } else {
        // log_enerji <= -0.673153 ?
        if (f[1] <= -0.673153) {
          // bant_enerji_orani <= 0.109449 ?
          if (f[3] <= 0.109449) {
            return 0.955010;
          } else {
            return 0.289855;
          }
        } else {
          // log_enerji <= 0.836234 ?
          if (f[1] <= 0.836234) {
            return 0.995025;
          } else {
            return 0.950124;
          }
        }
      }
    }
  }
}

double _agac4(List<double> f) {
  // log_enerji <= -1.129840 ?
  if (f[1] <= -1.129840) {
    // log_enerji <= -1.424573 ?
    if (f[1] <= -1.424573) {
      // sifir_gecis_orani <= 0.430000 ?
      if (f[2] <= 0.430000) {
        // log_enerji <= -1.771615 ?
        if (f[1] <= -1.771615) {
          // bant_enerji_orani <= 0.031714 ?
          if (f[3] <= 0.031714) {
            return 0.005102;
          } else {
            return 0.000194;
          }
        } else {
          // sta_lta_orani <= 0.066479 ?
          if (f[0] <= 0.066479) {
            return 0.388060;
          } else {
            return 0.033040;
          }
        }
      } else {
        return 1.000000;
      }
    } else {
      // bant_enerji_orani <= 0.070928 ?
      if (f[3] <= 0.070928) {
        // sta_lta_orani <= 0.295973 ?
        if (f[0] <= 0.295973) {
          // sifir_gecis_orani <= 0.210000 ?
          if (f[2] <= 0.210000) {
            return 0.652174;
          } else {
            return 0.982759;
          }
        } else {
          // sifir_gecis_orani <= 0.250000 ?
          if (f[2] <= 0.250000) {
            return 0.165730;
          } else {
            return 0.567164;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.330000 ?
        if (f[2] <= 0.330000) {
          // sta_lta_orani <= 0.192464 ?
          if (f[0] <= 0.192464) {
            return 0.684211;
          } else {
            return 0.059231;
          }
        } else {
          // bant_enerji_orani <= 0.094623 ?
          if (f[3] <= 0.094623) {
            return 0.166667;
          } else {
            return 1.000000;
          }
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sta_lta_orani <= 1.376768 ?
      if (f[0] <= 1.376768) {
        // bant_enerji_orani <= 0.055799 ?
        if (f[3] <= 0.055799) {
          // sta_lta_orani <= 0.675288 ?
          if (f[0] <= 0.675288) {
            return 0.919796;
          } else {
            return 0.396736;
          }
        } else {
          // log_enerji <= 0.694343 ?
          if (f[1] <= 0.694343) {
            return 0.842171;
          } else {
            return 0.145080;
          }
        }
      } else {
        // log_enerji <= -0.403481 ?
        if (f[1] <= -0.403481) {
          // sta_lta_orani <= 2.342030 ?
          if (f[0] <= 2.342030) {
            return 0.418018;
          } else {
            return 0.076775;
          }
        } else {
          // sta_lta_orani <= 1.546599 ?
          if (f[0] <= 1.546599) {
            return 0.689365;
          } else {
            return 0.934283;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.079985 ?
      if (f[3] <= 0.079985) {
        // log_enerji <= 0.810931 ?
        if (f[1] <= 0.810931) {
          // log_enerji <= -0.672371 ?
          if (f[1] <= -0.672371) {
            return 0.892265;
          } else {
            return 0.995098;
          }
        } else {
          // sta_lta_orani <= 1.377663 ?
          if (f[0] <= 1.377663) {
            return 0.856758;
          } else {
            return 0.997645;
          }
        }
      } else {
        // log_enerji <= 1.613579 ?
        if (f[1] <= 1.613579) {
          // sta_lta_orani <= 1.300180 ?
          if (f[0] <= 1.300180) {
            return 0.624750;
          } else {
            return 0.900726;
          }
        } else {
          return 1.000000;
        }
      }
    }
  }
}

double _agac5(List<double> f) {
  // sifir_gecis_orani <= 0.310000 ?
  if (f[2] <= 0.310000) {
    // sta_lta_orani <= 1.377835 ?
    if (f[0] <= 1.377835) {
      // log_enerji <= -1.202903 ?
      if (f[1] <= -1.202903) {
        // bant_enerji_orani <= 0.212100 ?
        if (f[3] <= 0.212100) {
          // log_enerji <= -1.454560 ?
          if (f[1] <= -1.454560) {
            return 0.005391;
          } else {
            return 0.174384;
          }
        } else {
          // bant_enerji_orani <= 0.212386 ?
          if (f[3] <= 0.212386) {
            return 1.000000;
          } else {
            return 0.066964;
          }
        }
      } else {
        // log_enerji <= 0.694580 ?
        if (f[1] <= 0.694580) {
          // sifir_gecis_orani <= 0.110000 ?
          if (f[2] <= 0.110000) {
            return 0.744013;
          } else {
            return 0.928915;
          }
        } else {
          // sta_lta_orani <= 0.680151 ?
          if (f[0] <= 0.680151) {
            return 0.730228;
          } else {
            return 0.158097;
          }
        }
      }
    } else {
      // log_enerji <= -0.423046 ?
      if (f[1] <= -0.423046) {
        // bant_enerji_orani <= 0.097382 ?
        if (f[3] <= 0.097382) {
          // sifir_gecis_orani <= 0.250000 ?
          if (f[2] <= 0.250000) {
            return 0.178571;
          } else {
            return 0.361111;
          }
        } else {
          // bant_enerji_orani <= 0.109072 ?
          if (f[3] <= 0.109072) {
            return 0.092437;
          } else {
            return 0.028446;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.030000 ?
        if (f[2] <= 0.030000) {
          // bant_enerji_orani <= 0.111683 ?
          if (f[3] <= 0.111683) {
            return 0.460000;
          } else {
            return 0.105263;
          }
        } else {
          // log_enerji <= 0.017661 ?
          if (f[1] <= 0.017661) {
            return 0.770115;
          } else {
            return 0.954543;
          }
        }
      }
    }
  } else {
    // sta_lta_orani <= 0.229054 ?
    if (f[0] <= 0.229054) {
      // bant_enerji_orani <= 0.050699 ?
      if (f[3] <= 0.050699) {
        // sifir_gecis_orani <= 0.350000 ?
        if (f[2] <= 0.350000) {
          // log_enerji <= -1.503391 ?
          if (f[1] <= -1.503391) {
            return 0.032787;
          } else {
            return 1.000000;
          }
        } else {
          // log_enerji <= -1.841987 ?
          if (f[1] <= -1.841987) {
            return 0.000000;
          } else {
            return 1.000000;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.410000 ?
        if (f[2] <= 0.410000) {
          // log_enerji <= -1.613577 ?
          if (f[1] <= -1.613577) {
            return 0.005391;
          } else {
            return 0.979310;
          }
        } else {
          return 1.000000;
        }
      }
    } else {
      // sifir_gecis_orani <= 0.350000 ?
      if (f[2] <= 0.350000) {
        // log_enerji <= -1.179747 ?
        if (f[1] <= -1.179747) {
          // log_enerji <= -1.536919 ?
          if (f[1] <= -1.536919) {
            return 0.000000;
          } else {
            return 0.340000;
          }
        } else {
          // log_enerji <= 1.254374 ?
          if (f[1] <= 1.254374) {
            return 0.993728;
          } else {
            return 0.961214;
          }
        }
      } else {
        // log_enerji <= -1.664145 ?
        if (f[1] <= -1.664145) {
          return 0.000000;
        } else {
          // sifir_gecis_orani <= 0.390000 ?
          if (f[2] <= 0.390000) {
            return 0.991049;
          } else {
            return 1.000000;
          }
        }
      }
    }
  }
}

double _agac6(List<double> f) {
  // log_enerji <= -1.105151 ?
  if (f[1] <= -1.105151) {
    // sifir_gecis_orani <= 0.430000 ?
    if (f[2] <= 0.430000) {
      // log_enerji <= -1.410103 ?
      if (f[1] <= -1.410103) {
        // sifir_gecis_orani <= 0.370000 ?
        if (f[2] <= 0.370000) {
          // log_enerji <= -1.542377 ?
          if (f[1] <= -1.542377) {
            return 0.002977;
          } else {
            return 0.059574;
          }
        } else {
          // log_enerji <= -1.661958 ?
          if (f[1] <= -1.661958) {
            return 0.000000;
          } else {
            return 0.785714;
          }
        }
      } else {
        // bant_enerji_orani <= 0.065288 ?
        if (f[3] <= 0.065288) {
          // sta_lta_orani <= 0.866324 ?
          if (f[0] <= 0.866324) {
            return 0.675958;
          } else {
            return 0.100559;
          }
        } else {
          // sta_lta_orani <= 0.233513 ?
          if (f[0] <= 0.233513) {
            return 0.563953;
          } else {
            return 0.070855;
          }
        }
      }
    } else {
      return 1.000000;
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sta_lta_orani <= 1.376193 ?
      if (f[0] <= 1.376193) {
        // sta_lta_orani <= 0.710225 ?
        if (f[0] <= 0.710225) {
          // sta_lta_orani <= 0.576178 ?
          if (f[0] <= 0.576178) {
            return 0.905432;
          } else {
            return 0.609309;
          }
        } else {
          // log_enerji <= 0.645614 ?
          if (f[1] <= 0.645614) {
            return 0.845280;
          } else {
            return 0.131722;
          }
        }
      } else {
        // log_enerji <= -0.403481 ?
        if (f[1] <= -0.403481) {
          // bant_enerji_orani <= 0.109928 ?
          if (f[3] <= 0.109928) {
            return 0.301144;
          } else {
            return 0.056296;
          }
        } else {
          // sta_lta_orani <= 1.537283 ?
          if (f[0] <= 1.537283) {
            return 0.672330;
          } else {
            return 0.935198;
          }
        }
      }
    } else {
      // sifir_gecis_orani <= 0.250000 ?
      if (f[2] <= 0.250000) {
        // sta_lta_orani <= 1.396811 ?
        if (f[0] <= 1.396811) {
          // log_enerji <= 0.783660 ?
          if (f[1] <= 0.783660) {
            return 0.955949;
          } else {
            return 0.419476;
          }
        } else {
          // log_enerji <= -0.658014 ?
          if (f[1] <= -0.658014) {
            return 0.131783;
          } else {
            return 0.976865;
          }
        }
      } else {
        // bant_enerji_orani <= 0.085085 ?
        if (f[3] <= 0.085085) {
          // sifir_gecis_orani <= 0.290000 ?
          if (f[2] <= 0.290000) {
            return 0.972231;
          } else {
            return 0.997516;
          }
        } else {
          // sta_lta_orani <= 1.349925 ?
          if (f[0] <= 1.349925) {
            return 0.752918;
          } else {
            return 0.952722;
          }
        }
      }
    }
  }
}

double _agac7(List<double> f) {
  // log_enerji <= -1.173524 ?
  if (f[1] <= -1.173524) {
    // log_enerji <= -1.426063 ?
    if (f[1] <= -1.426063) {
      // log_enerji <= -1.762478 ?
      if (f[1] <= -1.762478) {
        // log_enerji <= -1.819980 ?
        if (f[1] <= -1.819980) {
          return 0.000000;
        } else {
          // sta_lta_orani <= 0.031648 ?
          if (f[0] <= 0.031648) {
            return 0.187500;
          } else {
            return 0.001689;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.350000 ?
        if (f[2] <= 0.350000) {
          // bant_enerji_orani <= 0.078757 ?
          if (f[3] <= 0.078757) {
            return 0.058402;
          } else {
            return 0.011422;
          }
        } else {
          // sta_lta_orani <= 0.443563 ?
          if (f[0] <= 0.443563) {
            return 0.960000;
          } else {
            return 0.125000;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.065291 ?
      if (f[3] <= 0.065291) {
        // sta_lta_orani <= 0.595731 ?
        if (f[0] <= 0.595731) {
          // log_enerji <= -1.251464 ?
          if (f[1] <= -1.251464) {
            return 0.597315;
          } else {
            return 0.822581;
          }
        } else {
          // sifir_gecis_orani <= 0.330000 ?
          if (f[2] <= 0.330000) {
            return 0.080000;
          } else {
            return 1.000000;
          }
        }
      } else {
        // bant_enerji_orani <= 0.094333 ?
        if (f[3] <= 0.094333) {
          // sta_lta_orani <= 1.045751 ?
          if (f[0] <= 1.045751) {
            return 0.259398;
          } else {
            return 0.000000;
          }
        } else {
          // sta_lta_orani <= 0.155941 ?
          if (f[0] <= 0.155941) {
            return 0.441860;
          } else {
            return 0.031579;
          }
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sifir_gecis_orani <= 0.130000 ?
      if (f[2] <= 0.130000) {
        // sta_lta_orani <= 1.377084 ?
        if (f[0] <= 1.377084) {
          // log_enerji <= 0.621452 ?
          if (f[1] <= 0.621452) {
            return 0.824939;
          } else {
            return 0.152897;
          }
        } else {
          // sifir_gecis_orani <= 0.030000 ?
          if (f[2] <= 0.030000) {
            return 0.219780;
          } else {
            return 0.774518;
          }
        }
      } else {
        // sta_lta_orani <= 1.393867 ?
        if (f[0] <= 1.393867) {
          // sta_lta_orani <= 0.680902 ?
          if (f[0] <= 0.680902) {
            return 0.888444;
          } else {
            return 0.314795;
          }
        } else {
          // log_enerji <= -0.420849 ?
          if (f[1] <= -0.420849) {
            return 0.187198;
          } else {
            return 0.958061;
          }
        }
      }
    } else {
      // sifir_gecis_orani <= 0.270000 ?
      if (f[2] <= 0.270000) {
        // bant_enerji_orani <= 0.078429 ?
        if (f[3] <= 0.078429) {
          // log_enerji <= -1.069777 ?
          if (f[1] <= -1.069777) {
            return 0.465753;
          } else {
            return 0.934844;
          }
        } else {
          // bant_enerji_orani <= 0.107045 ?
          if (f[3] <= 0.107045) {
            return 0.777543;
          } else {
            return 0.655865;
          }
        }
      } else {
        // log_enerji <= -0.918098 ?
        if (f[1] <= -0.918098) {
          // bant_enerji_orani <= 0.115797 ?
          if (f[3] <= 0.115797) {
            return 0.894231;
          } else {
            return 0.333333;
          }
        } else {
          // bant_enerji_orani <= 0.086282 ?
          if (f[3] <= 0.086282) {
            return 0.995357;
          } else {
            return 0.924407;
          }
        }
      }
    }
  }
}

double _agac8(List<double> f) {
  // log_enerji <= -1.174132 ?
  if (f[1] <= -1.174132) {
    // log_enerji <= -1.422571 ?
    if (f[1] <= -1.422571) {
      // log_enerji <= -1.762478 ?
      if (f[1] <= -1.762478) {
        // log_enerji <= -1.785305 ?
        if (f[1] <= -1.785305) {
          // log_enerji <= -1.925516 ?
          if (f[1] <= -1.925516) {
            return 0.000000;
          } else {
            return 0.004665;
          }
        } else {
          // sifir_gecis_orani <= 0.090000 ?
          if (f[2] <= 0.090000) {
            return 0.166667;
          } else {
            return 0.009174;
          }
        }
      } else {
        // sta_lta_orani <= 0.066478 ?
        if (f[0] <= 0.066478) {
          // bant_enerji_orani <= 0.133387 ?
          if (f[3] <= 0.133387) {
            return 0.660377;
          } else {
            return 0.045455;
          }
        } else {
          // sta_lta_orani <= 0.435700 ?
          if (f[0] <= 0.435700) {
            return 0.093194;
          } else {
            return 0.007543;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.080958 ?
      if (f[3] <= 0.080958) {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // sifir_gecis_orani <= 0.210000 ?
          if (f[2] <= 0.210000) {
            return 0.184091;
          } else {
            return 0.379310;
          }
        } else {
          // sta_lta_orani <= 0.952263 ?
          if (f[0] <= 0.952263) {
            return 0.859813;
          } else {
            return 0.166667;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.350000 ?
        if (f[2] <= 0.350000) {
          // sta_lta_orani <= 0.237874 ?
          if (f[0] <= 0.237874) {
            return 0.500000;
          } else {
            return 0.029724;
          }
        } else {
          return 1.000000;
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sifir_gecis_orani <= 0.130000 ?
      if (f[2] <= 0.130000) {
        // sta_lta_orani <= 1.376199 ?
        if (f[0] <= 1.376199) {
          // log_enerji <= 0.621452 ?
          if (f[1] <= 0.621452) {
            return 0.820969;
          } else {
            return 0.147059;
          }
        } else {
          // log_enerji <= -0.266693 ?
          if (f[1] <= -0.266693) {
            return 0.179283;
          } else {
            return 0.877954;
          }
        }
      } else {
        // bant_enerji_orani <= 0.087171 ?
        if (f[3] <= 0.087171) {
          // bant_enerji_orani <= 0.055913 ?
          if (f[3] <= 0.055913) {
            return 0.767597;
          } else {
            return 0.660397;
          }
        } else {
          // sta_lta_orani <= 1.487676 ?
          if (f[0] <= 1.487676) {
            return 0.336351;
          } else {
            return 0.802951;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.078426 ?
      if (f[3] <= 0.078426) {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // log_enerji <= -0.737240 ?
          if (f[1] <= -0.737240) {
            return 0.650485;
          } else {
            return 0.925103;
          }
        } else {
          // bant_enerji_orani <= 0.065491 ?
          if (f[3] <= 0.065491) {
            return 0.997028;
          } else {
            return 0.958092;
          }
        }
      } else {
        // sta_lta_orani <= 1.396649 ?
        if (f[0] <= 1.396649) {
          // sta_lta_orani <= 0.669929 ?
          if (f[0] <= 0.669929) {
            return 0.942761;
          } else {
            return 0.531067;
          }
        } else {
          // sifir_gecis_orani <= 0.290000 ?
          if (f[2] <= 0.290000) {
            return 0.917394;
          } else {
            return 0.984756;
          }
        }
      }
    }
  }
}

double _agac9(List<double> f) {
  // log_enerji <= -1.050363 ?
  if (f[1] <= -1.050363) {
    // log_enerji <= -1.404857 ?
    if (f[1] <= -1.404857) {
      // sifir_gecis_orani <= 0.410000 ?
      if (f[2] <= 0.410000) {
        // sifir_gecis_orani <= 0.350000 ?
        if (f[2] <= 0.350000) {
          // log_enerji <= -1.770515 ?
          if (f[1] <= -1.770515) {
            return 0.000588;
          } else {
            return 0.029983;
          }
        } else {
          // log_enerji <= -1.645666 ?
          if (f[1] <= -1.645666) {
            return 0.000000;
          } else {
            return 0.750000;
          }
        }
      } else {
        // bant_enerji_orani <= 0.056975 ?
        if (f[3] <= 0.056975) {
          return 1.000000;
        } else {
          // log_enerji <= -2.084325 ?
          if (f[1] <= -2.084325) {
            return 0.000000;
          } else {
            return 1.000000;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.076412 ?
      if (f[3] <= 0.076412) {
        // sta_lta_orani <= 0.854429 ?
        if (f[0] <= 0.854429) {
          // log_enerji <= -1.171305 ?
          if (f[1] <= -1.171305) {
            return 0.512195;
          } else {
            return 0.841176;
          }
        } else {
          // sta_lta_orani <= 1.377537 ?
          if (f[0] <= 1.377537) {
            return 0.278146;
          } else {
            return 0.000000;
          }
        }
      } else {
        // sta_lta_orani <= 0.265155 ?
        if (f[0] <= 0.265155) {
          // log_enerji <= -1.281571 ?
          if (f[1] <= -1.281571) {
            return 0.510204;
          } else {
            return 0.770492;
          }
        } else {
          // sta_lta_orani <= 0.847208 ?
          if (f[0] <= 0.847208) {
            return 0.195991;
          } else {
            return 0.014286;
          }
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sta_lta_orani <= 1.431102 ?
      if (f[0] <= 1.431102) {
        // sta_lta_orani <= 0.675427 ?
        if (f[0] <= 0.675427) {
          // log_enerji <= 0.639854 ?
          if (f[1] <= 0.639854) {
            return 0.917378;
          } else {
            return 0.639485;
          }
        } else {
          // log_enerji <= 0.639373 ?
          if (f[1] <= 0.639373) {
            return 0.862974;
          } else {
            return 0.139086;
          }
        }
      } else {
        // log_enerji <= -0.403433 ?
        if (f[1] <= -0.403433) {
          // sta_lta_orani <= 3.039707 ?
          if (f[0] <= 3.039707) {
            return 0.341308;
          } else {
            return 0.036290;
          }
        } else {
          // bant_enerji_orani <= 0.133459 ?
          if (f[3] <= 0.133459) {
            return 0.943758;
          } else {
            return 0.731355;
          }
        }
      }
    } else {
      // log_enerji <= 0.835657 ?
      if (f[1] <= 0.835657) {
        // log_enerji <= -0.737349 ?
        if (f[1] <= -0.737349) {
          // bant_enerji_orani <= 0.107836 ?
          if (f[3] <= 0.107836) {
            return 0.852373;
          } else {
            return 0.260870;
          }
        } else {
          // bant_enerji_orani <= 0.130645 ?
          if (f[3] <= 0.130645) {
            return 0.992101;
          } else {
            return 0.878182;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // sta_lta_orani <= 1.397757 ?
          if (f[0] <= 1.397757) {
            return 0.398922;
          } else {
            return 0.988537;
          }
        } else {
          // sta_lta_orani <= 1.259713 ?
          if (f[0] <= 1.259713) {
            return 0.848160;
          } else {
            return 0.995000;
          }
        }
      }
    }
  }
}

double _agac10(List<double> f) {
  // sta_lta_orani <= 1.377685 ?
  if (f[0] <= 1.377685) {
    // sifir_gecis_orani <= 0.310000 ?
    if (f[2] <= 0.310000) {
      // log_enerji <= -1.201727 ?
      if (f[1] <= -1.201727) {
        // log_enerji <= -1.488664 ?
        if (f[1] <= -1.488664) {
          // log_enerji <= -1.599347 ?
          if (f[1] <= -1.599347) {
            return 0.001623;
          } else {
            return 0.047486;
          }
        } else {
          // sta_lta_orani <= 0.195844 ?
          if (f[0] <= 0.195844) {
            return 0.571429;
          } else {
            return 0.109811;
          }
        }
      } else {
        // log_enerji <= 0.694478 ?
        if (f[1] <= 0.694478) {
          // sifir_gecis_orani <= 0.110000 ?
          if (f[2] <= 0.110000) {
            return 0.739189;
          } else {
            return 0.924661;
          }
        } else {
          // sta_lta_orani <= 0.648410 ?
          if (f[0] <= 0.648410) {
            return 0.802817;
          } else {
            return 0.161992;
          }
        }
      }
    } else {
      // log_enerji <= -1.536919 ?
      if (f[1] <= -1.536919) {
        // log_enerji <= -1.672189 ?
        if (f[1] <= -1.672189) {
          // bant_enerji_orani <= 0.074365 ?
          if (f[3] <= 0.074365) {
            return 0.000000;
          } else {
            return 0.007595;
          }
        } else {
          // log_enerji <= -1.599957 ?
          if (f[1] <= -1.599957) {
            return 1.000000;
          } else {
            return 0.291667;
          }
        }
      } else {
        // log_enerji <= -1.363290 ?
        if (f[1] <= -1.363290) {
          // sta_lta_orani <= 0.804848 ?
          if (f[0] <= 0.804848) {
            return 0.777778;
          } else {
            return 0.000000;
          }
        } else {
          // log_enerji <= 1.303876 ?
          if (f[1] <= 1.303876) {
            return 0.998857;
          } else {
            return 0.914661;
          }
        }
      }
    }
  } else {
    // log_enerji <= -0.421365 ?
    if (f[1] <= -0.421365) {
      // log_enerji <= -0.853016 ?
      if (f[1] <= -0.853016) {
        // sifir_gecis_orani <= 0.410000 ?
        if (f[2] <= 0.410000) {
          // sta_lta_orani <= 1.743874 ?
          if (f[0] <= 1.743874) {
            return 0.062392;
          } else {
            return 0.005224;
          }
        } else {
          return 1.000000;
        }
      } else {
        // bant_enerji_orani <= 0.109985 ?
        if (f[3] <= 0.109985) {
          // sifir_gecis_orani <= 0.250000 ?
          if (f[2] <= 0.250000) {
            return 0.391916;
          } else {
            return 0.858696;
          }
        } else {
          // sifir_gecis_orani <= 0.190000 ?
          if (f[2] <= 0.190000) {
            return 0.057065;
          } else {
            return 0.214286;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.109658 ?
      if (f[3] <= 0.109658) {
        // sifir_gecis_orani <= 0.030000 ?
        if (f[2] <= 0.030000) {
          // sta_lta_orani <= 3.025987 ?
          if (f[0] <= 3.025987) {
            return 0.789474;
          } else {
            return 0.138462;
          }
        } else {
          // bant_enerji_orani <= 0.005731 ?
          if (f[3] <= 0.005731) {
            return 0.000000;
          } else {
            return 0.968814;
          }
        }
      } else {
        // log_enerji <= 0.068606 ?
        if (f[1] <= 0.068606) {
          // bant_enerji_orani <= 0.146955 ?
          if (f[3] <= 0.146955) {
            return 0.666667;
          } else {
            return 0.319328;
          }
        } else {
          // sifir_gecis_orani <= 0.050000 ?
          if (f[2] <= 0.050000) {
            return 0.339130;
          } else {
            return 0.913319;
          }
        }
      }
    }
  }
}

double _agac11(List<double> f) {
  // log_enerji <= -1.083069 ?
  if (f[1] <= -1.083069) {
    // bant_enerji_orani <= 0.048552 ?
    if (f[3] <= 0.048552) {
      // bant_enerji_orani <= 0.048381 ?
      if (f[3] <= 0.048381) {
        // sta_lta_orani <= 1.209207 ?
        if (f[0] <= 1.209207) {
          // log_enerji <= -1.425486 ?
          if (f[1] <= -1.425486) {
            return 0.017743;
          } else {
            return 0.653659;
          }
        } else {
          return 0.000000;
        }
      } else {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // log_enerji <= -1.805643 ?
          if (f[1] <= -1.805643) {
            return 0.000000;
          } else {
            return 1.000000;
          }
        } else {
          return 1.000000;
        }
      }
    } else {
      // sifir_gecis_orani <= 0.350000 ?
      if (f[2] <= 0.350000) {
        // sta_lta_orani <= 1.103465 ?
        if (f[0] <= 1.103465) {
          // log_enerji <= -1.366977 ?
          if (f[1] <= -1.366977) {
            return 0.006131;
          } else {
            return 0.319149;
          }
        } else {
          // log_enerji <= -1.088205 ?
          if (f[1] <= -1.088205) {
            return 0.000520;
          } else {
            return 0.105263;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.430000 ?
        if (f[2] <= 0.430000) {
          // log_enerji <= -1.687344 ?
          if (f[1] <= -1.687344) {
            return 0.006061;
          } else {
            return 0.857143;
          }
        } else {
          return 1.000000;
        }
      }
    }
  } else {
    // sifir_gecis_orani <= 0.210000 ?
    if (f[2] <= 0.210000) {
      // sta_lta_orani <= 1.430715 ?
      if (f[0] <= 1.430715) {
        // log_enerji <= 0.694463 ?
        if (f[1] <= 0.694463) {
          // log_enerji <= -0.780157 ?
          if (f[1] <= -0.780157) {
            return 0.588172;
          } else {
            return 0.895860;
          }
        } else {
          // log_enerji <= 1.505086 ?
          if (f[1] <= 1.505086) {
            return 0.141147;
          } else {
            return 0.913863;
          }
        }
      } else {
        // log_enerji <= -0.268772 ?
        if (f[1] <= -0.268772) {
          // bant_enerji_orani <= 0.097770 ?
          if (f[3] <= 0.097770) {
            return 0.397327;
          } else {
            return 0.111111;
          }
        } else {
          // bant_enerji_orani <= 0.125816 ?
          if (f[3] <= 0.125816) {
            return 0.950154;
          } else {
            return 0.770968;
          }
        }
      }
    } else {
      // bant_enerji_orani <= 0.079109 ?
      if (f[3] <= 0.079109) {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // sta_lta_orani <= 1.371659 ?
          if (f[0] <= 1.371659) {
            return 0.856585;
          } else {
            return 0.968354;
          }
        } else {
          // log_enerji <= -1.000355 ?
          if (f[1] <= -1.000355) {
            return 0.818182;
          } else {
            return 0.992144;
          }
        }
      } else {
        // log_enerji <= 0.835309 ?
        if (f[1] <= 0.835309) {
          // sta_lta_orani <= 3.168574 ?
          if (f[0] <= 3.168574) {
            return 0.933471;
          } else {
            return 0.757979;
          }
        } else {
          // sta_lta_orani <= 1.333972 ?
          if (f[0] <= 1.333972) {
            return 0.290618;
          } else {
            return 0.984666;
          }
        }
      }
    }
  }
}

double _agac12(List<double> f) {
  // sta_lta_orani <= 1.376170 ?
  if (f[0] <= 1.376170) {
    // log_enerji <= -1.253184 ?
    if (f[1] <= -1.253184) {
      // sifir_gecis_orani <= 0.410000 ?
      if (f[2] <= 0.410000) {
        // sifir_gecis_orani <= 0.390000 ?
        if (f[2] <= 0.390000) {
          // log_enerji <= -1.471745 ?
          if (f[1] <= -1.471745) {
            return 0.004687;
          } else {
            return 0.161779;
          }
        } else {
          // sta_lta_orani <= 0.449909 ?
          if (f[0] <= 0.449909) {
            return 0.071429;
          } else {
            return 0.545455;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.430000 ?
        if (f[2] <= 0.430000) {
          // log_enerji <= -2.133828 ?
          if (f[1] <= -2.133828) {
            return 0.000000;
          } else {
            return 1.000000;
          }
        } else {
          return 1.000000;
        }
      }
    } else {
      // sifir_gecis_orani <= 0.210000 ?
      if (f[2] <= 0.210000) {
        // log_enerji <= 0.694386 ?
        if (f[1] <= 0.694386) {
          // log_enerji <= -0.849624 ?
          if (f[1] <= -0.849624) {
            return 0.471824;
          } else {
            return 0.888393;
          }
        } else {
          // log_enerji <= 1.513771 ?
          if (f[1] <= 1.513771) {
            return 0.138408;
          } else {
            return 0.920181;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // log_enerji <= 0.842332 ?
          if (f[1] <= 0.842332) {
            return 0.945601;
          } else {
            return 0.403557;
          }
        } else {
          // bant_enerji_orani <= 0.085085 ?
          if (f[3] <= 0.085085) {
            return 0.985585;
          } else {
            return 0.776770;
          }
        }
      }
    }
  } else {
    // log_enerji <= -0.470851 ?
    if (f[1] <= -0.470851) {
      // bant_enerji_orani <= 0.081521 ?
      if (f[3] <= 0.081521) {
        // log_enerji <= -0.778049 ?
        if (f[1] <= -0.778049) {
          // sta_lta_orani <= 1.387035 ?
          if (f[0] <= 1.387035) {
            return 1.000000;
          } else {
            return 0.066050;
          }
        } else {
          // sifir_gecis_orani <= 0.290000 ?
          if (f[2] <= 0.290000) {
            return 0.458716;
          } else {
            return 0.953488;
          }
        }
      } else {
        // bant_enerji_orani <= 0.108887 ?
        if (f[3] <= 0.108887) {
          // bant_enerji_orani <= 0.107137 ?
          if (f[3] <= 0.107137) {
            return 0.082061;
          } else {
            return 0.500000;
          }
        } else {
          // log_enerji <= -0.474536 ?
          if (f[1] <= -0.474536) {
            return 0.021152;
          } else {
            return 1.000000;
          }
        }
      }
    } else {
      // sifir_gecis_orani <= 0.030000 ?
      if (f[2] <= 0.030000) {
        // sta_lta_orani <= 3.338220 ?
        if (f[0] <= 3.338220) {
          // sta_lta_orani <= 1.575955 ?
          if (f[0] <= 1.575955) {
            return 1.000000;
          } else {
            return 0.494118;
          }
        } else {
          // sta_lta_orani <= 4.962284 ?
          if (f[0] <= 4.962284) {
            return 0.151515;
          } else {
            return 0.062500;
          }
        }
      } else {
        // log_enerji <= -0.273662 ?
        if (f[1] <= -0.273662) {
          // bant_enerji_orani <= 0.114366 ?
          if (f[3] <= 0.114366) {
            return 0.805897;
          } else {
            return 0.217391;
          }
        } else {
          // sta_lta_orani <= 1.536992 ?
          if (f[0] <= 1.536992) {
            return 0.766213;
          } else {
            return 0.973524;
          }
        }
      }
    }
  }
}

double _agac13(List<double> f) {
  // sta_lta_orani <= 1.374604 ?
  if (f[0] <= 1.374604) {
    // log_enerji <= -1.261972 ?
    if (f[1] <= -1.261972) {
      // log_enerji <= -1.495632 ?
      if (f[1] <= -1.495632) {
        // sta_lta_orani <= 0.428955 ?
        if (f[0] <= 0.428955) {
          // sifir_gecis_orani <= 0.440000 ?
          if (f[2] <= 0.440000) {
            return 0.007200;
          } else {
            return 1.000000;
          }
        } else {
          // sta_lta_orani <= 0.560838 ?
          if (f[0] <= 0.560838) {
            return 0.001608;
          } else {
            return 0.000000;
          }
        }
      } else {
        // bant_enerji_orani <= 0.071372 ?
        if (f[3] <= 0.071372) {
          // sifir_gecis_orani <= 0.230000 ?
          if (f[2] <= 0.230000) {
            return 0.224265;
          } else {
            return 0.663551;
          }
        } else {
          // sifir_gecis_orani <= 0.330000 ?
          if (f[2] <= 0.330000) {
            return 0.080263;
          } else {
            return 0.421053;
          }
        }
      }
    } else {
      // log_enerji <= 0.694478 ?
      if (f[1] <= 0.694478) {
        // sifir_gecis_orani <= 0.150000 ?
        if (f[2] <= 0.150000) {
          // log_enerji <= -0.859384 ?
          if (f[1] <= -0.859384) {
            return 0.418778;
          } else {
            return 0.840160;
          }
        } else {
          // sifir_gecis_orani <= 0.270000 ?
          if (f[2] <= 0.270000) {
            return 0.921439;
          } else {
            return 0.993841;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.250000 ?
        if (f[2] <= 0.250000) {
          // sta_lta_orani <= 0.649363 ?
          if (f[0] <= 0.649363) {
            return 0.747010;
          } else {
            return 0.147094;
          }
        } else {
          // bant_enerji_orani <= 0.079647 ?
          if (f[3] <= 0.079647) {
            return 0.982356;
          } else {
            return 0.609576;
          }
        }
      }
    }
  } else {
    // log_enerji <= -0.446260 ?
    if (f[1] <= -0.446260) {
      // log_enerji <= -0.735074 ?
      if (f[1] <= -0.735074) {
        // log_enerji <= -1.042135 ?
        if (f[1] <= -1.042135) {
          // log_enerji <= -1.078779 ?
          if (f[1] <= -1.078779) {
            return 0.000000;
          } else {
            return 0.029126;
          }
        } else {
          // bant_enerji_orani <= 0.083510 ?
          if (f[3] <= 0.083510) {
            return 0.252174;
          } else {
            return 0.022222;
          }
        }
      } else {
        // sta_lta_orani <= 3.444300 ?
        if (f[0] <= 3.444300) {
          // sifir_gecis_orani <= 0.090000 ?
          if (f[2] <= 0.090000) {
            return 0.210526;
          } else {
            return 0.606138;
          }
        } else {
          // sifir_gecis_orani <= 0.170000 ?
          if (f[2] <= 0.170000) {
            return 0.018116;
          } else {
            return 0.271605;
          }
        }
      }
    } else {
      // sta_lta_orani <= 1.537097 ?
      if (f[0] <= 1.537097) {
        // log_enerji <= 1.008712 ?
        if (f[1] <= 1.008712) {
          // sta_lta_orani <= 1.535993 ?
          if (f[0] <= 1.535993) {
            return 0.969940;
          } else {
            return 0.454545;
          }
        } else {
          // sifir_gecis_orani <= 0.230000 ?
          if (f[2] <= 0.230000) {
            return 0.423898;
          } else {
            return 0.910112;
          }
        }
      } else {
        // sifir_gecis_orani <= 0.030000 ?
        if (f[2] <= 0.030000) {
          // bant_enerji_orani <= 0.091497 ?
          if (f[3] <= 0.091497) {
            return 0.633028;
          } else {
            return 0.093750;
          }
        } else {
          // bant_enerji_orani <= 0.139716 ?
          if (f[3] <= 0.139716) {
            return 0.978174;
          } else {
            return 0.831754;
          }
        }
      }
    }
  }
}

double _agac14(List<double> f) {
  // sifir_gecis_orani <= 0.310000 ?
  if (f[2] <= 0.310000) {
    // log_enerji <= -1.055992 ?
    if (f[1] <= -1.055992) {
      // log_enerji <= -1.408525 ?
      if (f[1] <= -1.408525) {
        // log_enerji <= -1.766775 ?
        if (f[1] <= -1.766775) {
          // sifir_gecis_orani <= 0.090000 ?
          if (f[2] <= 0.090000) {
            return 0.009091;
          } else {
            return 0.000274;
          }
        } else {
          // log_enerji <= -1.766555 ?
          if (f[1] <= -1.766555) {
            return 1.000000;
          } else {
            return 0.036183;
          }
        }
      } else {
        // sta_lta_orani <= 0.247480 ?
        if (f[0] <= 0.247480) {
          // sifir_gecis_orani <= 0.110000 ?
          if (f[2] <= 0.110000) {
            return 0.423729;
          } else {
            return 0.801136;
          }
        } else {
          // bant_enerji_orani <= 0.071284 ?
          if (f[3] <= 0.071284) {
            return 0.265594;
          } else {
            return 0.067636;
          }
        }
      }
    } else {
      // log_enerji <= 0.694571 ?
      if (f[1] <= 0.694571) {
        // sta_lta_orani <= 3.047498 ?
        if (f[0] <= 3.047498) {
          // sifir_gecis_orani <= 0.110000 ?
          if (f[2] <= 0.110000) {
            return 0.758256;
          } else {
            return 0.929832;
          }
        } else {
          // bant_enerji_orani <= 0.115058 ?
          if (f[3] <= 0.115058) {
            return 0.725904;
          } else {
            return 0.255663;
          }
        }
      } else {
        // sta_lta_orani <= 1.435251 ?
        if (f[0] <= 1.435251) {
          // sta_lta_orani <= 0.649612 ?
          if (f[0] <= 0.649612) {
            return 0.768878;
          } else {
            return 0.168958;
          }
        } else {
          // sta_lta_orani <= 1.536362 ?
          if (f[0] <= 1.536362) {
            return 0.631206;
          } else {
            return 0.979461;
          }
        }
      }
    }
  } else {
    // log_enerji <= -1.668873 ?
    if (f[1] <= -1.668873) {
      // sta_lta_orani <= 0.148250 ?
      if (f[0] <= 0.148250) {
        return 0.000000;
      } else {
        // log_enerji <= -1.731873 ?
        if (f[1] <= -1.731873) {
          // sta_lta_orani <= 0.165118 ?
          if (f[0] <= 0.165118) {
            return 0.055556;
          } else {
            return 0.000000;
          }
        } else {
          // bant_enerji_orani <= 0.077484 ?
          if (f[3] <= 0.077484) {
            return 0.571429;
          } else {
            return 0.000000;
          }
        }
      }
    } else {
      // sifir_gecis_orani <= 0.350000 ?
      if (f[2] <= 0.350000) {
        // sta_lta_orani <= 1.243786 ?
        if (f[0] <= 1.243786) {
          // bant_enerji_orani <= 0.090743 ?
          if (f[3] <= 0.090743) {
            return 0.982990;
          } else {
            return 0.750000;
          }
        } else {
          // bant_enerji_orani <= 0.136687 ?
          if (f[3] <= 0.136687) {
            return 0.994577;
          } else {
            return 0.912621;
          }
        }
      } else {
        // log_enerji <= -1.363105 ?
        if (f[1] <= -1.363105) {
          // log_enerji <= -1.364945 ?
          if (f[1] <= -1.364945) {
            return 0.925000;
          } else {
            return 0.000000;
          }
        } else {
          // log_enerji <= -0.919784 ?
          if (f[1] <= -0.919784) {
            return 0.960938;
          } else {
            return 0.999447;
          }
        }
      }
    }
  }
}
