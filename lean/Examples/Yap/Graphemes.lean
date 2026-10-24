module

/-! # Yap: characters as Swift counts them

Swift's `Character` is an extended grapheme cluster (Unicode's UAX #29), and Yap counts and
cuts text in them: "Typed N characters", the Recent Transcripts labels (60 characters), the
preview's context (the last 200) and `hasPrefix("#")` in `dictionary.txt`. This is Swift's
segmentation (`StringGraphemeBreaking.swift`), quirks included: its rule GB9c knows only six
viramas, and walking backwards (`suffix`) it has its own lookback rules.

`table` lists, from each code point where the properties change, a class: the
Grapheme_Cluster_Break value (0 other, 1 CR, 2 LF, 3 control, 4 extend, 5 ZWJ, 6 regional
indicator, 7 prepend, 8 spacing mark, 9 to 13 the Hangul L, V, T, LV and LVT), plus 16 for
Extended_Pictographic, plus 32, 64 or 96 for Indic_Conjunct_Break Consonant, Extend or Linker.
Swift's stdlib doesn't export its tables, so each code point's class was found by asking Swift
how it segments the code point beside probes ("a" then it, it then U+0301, a flag then it, …;
docs/yap-parity.md), and the segmentation checked against Swift's `String.count`, `prefix` and
`suffix` on Unicode 17's GraphemeBreakTest and 60,000 random strings. -/

@[expose] public section

namespace Examples.Yap.Graphemes

/-- Code point, class; from each code point to the next entry's. -/
def tableText : String :=
  "0:3 a:2 b:3 d:1 e:3 20:0 7f:3 a0:0 a9:16 aa:0 ad:3 ae:16 af:0 300:4 370:0 483:4 48a:0 591:4 " ++
  "5be:0 5bf:4 5c0:0 5c1:4 5c3:0 5c4:4 5c6:0 5c7:4 5c8:0 600:7 606:0 610:4 61b:0 61c:3 61d:0 64b:4 " ++
  "660:0 670:4 671:0 6d6:4 6dd:7 6de:0 6df:4 6e5:0 6e7:4 6e9:0 6ea:4 6ee:0 70f:7 710:0 711:4 712:0 " ++
  "730:4 74b:0 7a6:4 7b1:0 7eb:4 7f4:0 7fd:4 7fe:0 816:4 81a:0 81b:4 824:0 825:4 828:0 829:4 82e:0 " ++
  "859:4 85c:0 890:7 892:0 897:4 8a0:0 8ca:4 8e2:7 8e3:4 903:8 904:0 915:32 93a:4 93b:8 93c:4 " ++
  "93d:0 93e:8 941:4 949:8 94d:100 94e:8 950:0 951:4 958:32 960:0 962:4 964:0 978:32 980:0 981:4 " ++
  "982:8 984:0 995:32 9a9:0 9aa:32 9b1:0 9b2:32 9b3:0 9b6:32 9ba:0 9bc:4 9bd:0 9be:4 9bf:8 9c1:4 " ++
  "9c5:0 9c7:8 9c9:0 9cb:8 9cd:100 9ce:0 9d7:4 9d8:0 9dc:32 9de:0 9df:32 9e0:0 9e2:4 9e4:0 9f0:32 " ++
  "9f2:0 9fe:4 9ff:0 a01:4 a03:8 a04:0 a3c:4 a3d:0 a3e:8 a41:4 a43:0 a47:4 a49:0 a4b:4 a4e:0 a51:4 " ++
  "a52:0 a70:4 a72:0 a75:4 a76:0 a81:4 a83:8 a84:0 a95:32 aa9:0 aaa:32 ab1:0 ab2:32 ab4:0 ab5:32 " ++
  "aba:0 abc:4 abd:0 abe:8 ac1:4 ac6:0 ac7:4 ac9:8 aca:0 acb:8 acd:100 ace:0 ae2:4 ae4:0 af9:32 " ++
  "afa:4 b00:0 b01:4 b02:8 b04:0 b15:32 b29:0 b2a:32 b31:0 b32:32 b34:0 b35:32 b3a:0 b3c:4 b3d:0 " ++
  "b3e:4 b40:8 b41:4 b45:0 b47:8 b49:0 b4b:8 b4d:100 b4e:0 b55:4 b58:0 b5c:32 b5e:0 b5f:32 b60:0 " ++
  "b62:4 b64:0 b71:32 b72:0 b82:4 b83:0 bbe:4 bbf:8 bc0:4 bc1:8 bc3:0 bc6:8 bc9:0 bca:8 bcd:4 " ++
  "bce:0 bd7:4 bd8:0 c00:4 c01:8 c04:4 c05:0 c15:32 c29:0 c2a:32 c3a:0 c3c:4 c3d:0 c3e:4 c41:8 " ++
  "c45:0 c46:4 c49:0 c4a:4 c4d:100 c4e:0 c55:4 c57:0 c58:32 c5b:0 c62:4 c64:0 c81:4 c82:8 c84:0 " ++
  "cbc:4 cbd:0 cbe:8 cbf:4 cc1:8 cc2:4 cc3:8 cc5:0 cc6:4 cc9:0 cca:4 cce:0 cd5:4 cd7:0 ce2:4 ce4:0 " ++
  "cf3:8 cf4:0 d00:4 d02:8 d04:0 d15:32 d3b:4 d3d:0 d3e:4 d3f:8 d41:4 d45:0 d46:8 d49:0 d4a:8 " ++
  "d4d:100 d4e:7 d4f:0 d57:4 d58:0 d62:4 d64:0 d81:4 d82:8 d84:0 dca:4 dcb:0 dcf:4 dd0:8 dd2:4 " ++
  "dd5:0 dd6:4 dd7:0 dd8:8 ddf:4 de0:0 df2:8 df4:0 e31:4 e32:0 e33:8 e34:4 e3b:0 e47:4 e4f:0 eb1:4 " ++
  "eb2:0 eb3:8 eb4:4 ebd:0 ec8:4 ecf:0 f18:4 f1a:0 f35:4 f36:0 f37:4 f38:0 f39:4 f3a:0 f3e:8 f40:0 " ++
  "f71:4 f7f:8 f80:4 f85:0 f86:4 f88:0 f8d:4 f98:0 f99:4 fbd:0 fc6:4 fc7:0 1000:32 102b:0 102d:4 " ++
  "1031:8 1032:4 1038:0 1039:4 103b:8 103d:4 103f:32 1040:0 1050:32 1056:8 1058:4 105a:32 105e:4 " ++
  "1061:32 1062:0 1065:32 1067:0 106e:32 1071:4 1075:32 1082:4 1083:0 1084:8 1085:4 1087:0 108d:4 " ++
  "108e:32 108f:0 109d:4 109e:0 1100:9 1160:10 11a8:11 1200:0 135d:4 1360:0 1712:4 1716:0 1732:4 " ++
  "1735:0 1752:4 1754:0 1772:4 1774:0 1780:32 17b4:4 17b6:8 17b7:4 17be:8 17c6:4 17c7:8 17c9:4 " ++
  "17d4:0 17dd:4 17de:0 180b:4 180e:3 180f:4 1810:0 1885:4 1887:0 18a9:4 18aa:0 1920:4 1923:8 " ++
  "1927:4 1929:8 192c:0 1930:8 1932:4 1933:8 1939:4 193c:0 1a17:4 1a19:8 1a1b:4 1a1c:0 1a20:32 " ++
  "1a55:8 1a56:4 1a57:8 1a58:4 1a5f:0 1a60:4 1a61:0 1a62:4 1a63:0 1a65:4 1a6d:8 1a73:4 1a7d:0 " ++
  "1a7f:4 1a80:0 1ab0:4 1ade:0 1ae0:4 1aec:0 1b00:4 1b04:8 1b05:0 1b0b:32 1b0d:0 1b13:32 1b34:4 " ++
  "1b3e:8 1b42:4 1b45:32 1b4d:0 1b6b:4 1b74:0 1b80:4 1b82:8 1b83:32 1ba1:8 1ba2:4 1ba6:8 1ba8:4 " ++
  "1bae:32 1bb0:0 1bbb:32 1bbe:0 1be6:4 1be7:8 1be8:4 1bea:8 1bed:4 1bee:8 1bef:4 1bf4:0 1c24:8 " ++
  "1c2c:4 1c34:8 1c36:4 1c38:0 1cd0:4 1cd3:0 1cd4:4 1ce1:8 1ce2:4 1ce9:0 1ced:4 1cee:0 1cf4:4 " ++
  "1cf5:0 1cf7:8 1cf8:4 1cfa:0 1dc0:4 1e00:0 200b:3 200c:4 200d:5 200e:3 2010:0 2028:3 202f:0 " ++
  "203c:16 203d:0 2049:16 204a:0 2060:3 2070:0 20d0:4 20f1:0 2122:16 2123:0 2139:16 213a:0 2194:16 " ++
  "219a:0 21a9:16 21ab:0 231a:16 231c:0 2328:16 2329:0 23cf:16 23d0:0 23e9:16 23f4:0 23f8:16 " ++
  "23fb:0 24c2:16 24c3:0 25aa:16 25ac:0 25b6:16 25b7:0 25c0:16 25c1:0 25fb:16 25ff:0 2600:16 " ++
  "2605:0 260e:16 260f:0 2611:16 2612:0 2614:16 2616:0 2618:16 2619:0 261d:16 261e:0 2620:16 " ++
  "2621:0 2622:16 2624:0 2626:16 2627:0 262a:16 262b:0 262e:16 2630:0 2638:16 263b:0 2640:16 " ++
  "2641:0 2642:16 2643:0 2648:16 2654:0 265f:16 2661:0 2663:16 2664:0 2665:16 2667:0 2668:16 " ++
  "2669:0 267b:16 267c:0 267e:16 2680:0 2692:16 2698:0 2699:16 269a:0 269b:16 269d:0 26a0:16 " ++
  "26a2:0 26a7:16 26a8:0 26aa:16 26ac:0 26b0:16 26b2:0 26bd:16 26bf:0 26c4:16 26c6:0 26c8:16 " ++
  "26c9:0 26ce:16 26d0:0 26d1:16 26d2:0 26d3:16 26d5:0 26e9:16 26eb:0 26f0:16 26f6:0 26f7:16 " ++
  "26fb:0 26fd:16 26fe:0 2702:16 2703:0 2705:16 2706:0 2708:16 270e:0 270f:16 2710:0 2712:16 " ++
  "2713:0 2714:16 2715:0 2716:16 2717:0 271d:16 271e:0 2721:16 2722:0 2728:16 2729:0 2733:16 " ++
  "2735:0 2744:16 2745:0 2747:16 2748:0 274c:16 274d:0 274e:16 274f:0 2753:16 2756:0 2757:16 " ++
  "2758:0 2763:16 2765:0 2795:16 2798:0 27a1:16 27a2:0 27b0:16 27b1:0 27bf:16 27c0:0 2934:16 " ++
  "2936:0 2b05:16 2b08:0 2b1b:16 2b1d:0 2b50:16 2b51:0 2b55:16 2b56:0 2cef:4 2cf2:0 2d7f:4 2d80:0 " ++
  "2de0:4 2e00:0 302a:4 3030:16 3031:0 303d:16 303e:0 3099:4 309b:0 3297:16 3298:0 3299:16 329a:0 " ++
  "a66f:4 a673:0 a674:4 a67e:0 a69e:4 a6a0:0 a6f0:4 a6f2:0 a802:4 a803:0 a806:4 a807:0 a80b:4 " ++
  "a80c:0 a823:8 a825:4 a827:8 a828:0 a82c:4 a82d:0 a880:8 a882:0 a8b4:8 a8c4:4 a8c6:0 a8e0:4 " ++
  "a8f2:0 a8ff:4 a900:0 a926:4 a92e:0 a947:4 a952:8 a953:4 a954:0 a960:9 a97d:0 a980:4 a983:8 " ++
  "a984:0 a989:32 a98c:0 a98f:32 a9b3:4 a9b4:8 a9b6:4 a9ba:8 a9bc:4 a9be:8 a9c0:4 a9c1:0 a9e0:32 " ++
  "a9e5:4 a9e6:0 a9e7:32 a9f0:0 a9fa:32 a9ff:0 aa29:4 aa2f:8 aa31:4 aa33:8 aa35:4 aa37:0 aa43:4 " ++
  "aa44:0 aa4c:4 aa4d:8 aa4e:0 aa60:32 aa70:0 aa71:32 aa74:0 aa7a:32 aa7b:0 aa7c:4 aa7d:0 aa7e:32 " ++
  "aa80:0 aab0:4 aab1:0 aab2:4 aab5:0 aab7:4 aab9:0 aabe:4 aac0:0 aac1:4 aac2:0 aae0:32 aaeb:8 " ++
  "aaec:4 aaee:8 aaf0:0 aaf5:8 aaf6:4 aaf7:0 abc0:32 abdb:0 abe3:8 abe5:4 abe6:8 abe8:4 abe9:8 " ++
  "abeb:0 abec:8 abed:4 abee:0 ac00:12 ac01:13 ac1c:12 ac1d:13 ac38:12 ac39:13 ac54:12 ac55:13 " ++
  "ac70:12 ac71:13 ac8c:12 ac8d:13 aca8:12 aca9:13 acc4:12 acc5:13 ace0:12 ace1:13 acfc:12 acfd:13 " ++
  "ad18:12 ad19:13 ad34:12 ad35:13 ad50:12 ad51:13 ad6c:12 ad6d:13 ad88:12 ad89:13 ada4:12 ada5:13 " ++
  "adc0:12 adc1:13 addc:12 addd:13 adf8:12 adf9:13 ae14:12 ae15:13 ae30:12 ae31:13 ae4c:12 ae4d:13 " ++
  "ae68:12 ae69:13 ae84:12 ae85:13 aea0:12 aea1:13 aebc:12 aebd:13 aed8:12 aed9:13 aef4:12 aef5:13 " ++
  "af10:12 af11:13 af2c:12 af2d:13 af48:12 af49:13 af64:12 af65:13 af80:12 af81:13 af9c:12 af9d:13 " ++
  "afb8:12 afb9:13 afd4:12 afd5:13 aff0:12 aff1:13 b00c:12 b00d:13 b028:12 b029:13 b044:12 b045:13 " ++
  "b060:12 b061:13 b07c:12 b07d:13 b098:12 b099:13 b0b4:12 b0b5:13 b0d0:12 b0d1:13 b0ec:12 b0ed:13 " ++
  "b108:12 b109:13 b124:12 b125:13 b140:12 b141:13 b15c:12 b15d:13 b178:12 b179:13 b194:12 b195:13 " ++
  "b1b0:12 b1b1:13 b1cc:12 b1cd:13 b1e8:12 b1e9:13 b204:12 b205:13 b220:12 b221:13 b23c:12 b23d:13 " ++
  "b258:12 b259:13 b274:12 b275:13 b290:12 b291:13 b2ac:12 b2ad:13 b2c8:12 b2c9:13 b2e4:12 b2e5:13 " ++
  "b300:12 b301:13 b31c:12 b31d:13 b338:12 b339:13 b354:12 b355:13 b370:12 b371:13 b38c:12 b38d:13 " ++
  "b3a8:12 b3a9:13 b3c4:12 b3c5:13 b3e0:12 b3e1:13 b3fc:12 b3fd:13 b418:12 b419:13 b434:12 b435:13 " ++
  "b450:12 b451:13 b46c:12 b46d:13 b488:12 b489:13 b4a4:12 b4a5:13 b4c0:12 b4c1:13 b4dc:12 b4dd:13 " ++
  "b4f8:12 b4f9:13 b514:12 b515:13 b530:12 b531:13 b54c:12 b54d:13 b568:12 b569:13 b584:12 b585:13 " ++
  "b5a0:12 b5a1:13 b5bc:12 b5bd:13 b5d8:12 b5d9:13 b5f4:12 b5f5:13 b610:12 b611:13 b62c:12 b62d:13 " ++
  "b648:12 b649:13 b664:12 b665:13 b680:12 b681:13 b69c:12 b69d:13 b6b8:12 b6b9:13 b6d4:12 b6d5:13 " ++
  "b6f0:12 b6f1:13 b70c:12 b70d:13 b728:12 b729:13 b744:12 b745:13 b760:12 b761:13 b77c:12 b77d:13 " ++
  "b798:12 b799:13 b7b4:12 b7b5:13 b7d0:12 b7d1:13 b7ec:12 b7ed:13 b808:12 b809:13 b824:12 b825:13 " ++
  "b840:12 b841:13 b85c:12 b85d:13 b878:12 b879:13 b894:12 b895:13 b8b0:12 b8b1:13 b8cc:12 b8cd:13 " ++
  "b8e8:12 b8e9:13 b904:12 b905:13 b920:12 b921:13 b93c:12 b93d:13 b958:12 b959:13 b974:12 b975:13 " ++
  "b990:12 b991:13 b9ac:12 b9ad:13 b9c8:12 b9c9:13 b9e4:12 b9e5:13 ba00:12 ba01:13 ba1c:12 ba1d:13 " ++
  "ba38:12 ba39:13 ba54:12 ba55:13 ba70:12 ba71:13 ba8c:12 ba8d:13 baa8:12 baa9:13 bac4:12 bac5:13 " ++
  "bae0:12 bae1:13 bafc:12 bafd:13 bb18:12 bb19:13 bb34:12 bb35:13 bb50:12 bb51:13 bb6c:12 bb6d:13 " ++
  "bb88:12 bb89:13 bba4:12 bba5:13 bbc0:12 bbc1:13 bbdc:12 bbdd:13 bbf8:12 bbf9:13 bc14:12 bc15:13 " ++
  "bc30:12 bc31:13 bc4c:12 bc4d:13 bc68:12 bc69:13 bc84:12 bc85:13 bca0:12 bca1:13 bcbc:12 bcbd:13 " ++
  "bcd8:12 bcd9:13 bcf4:12 bcf5:13 bd10:12 bd11:13 bd2c:12 bd2d:13 bd48:12 bd49:13 bd64:12 bd65:13 " ++
  "bd80:12 bd81:13 bd9c:12 bd9d:13 bdb8:12 bdb9:13 bdd4:12 bdd5:13 bdf0:12 bdf1:13 be0c:12 be0d:13 " ++
  "be28:12 be29:13 be44:12 be45:13 be60:12 be61:13 be7c:12 be7d:13 be98:12 be99:13 beb4:12 beb5:13 " ++
  "bed0:12 bed1:13 beec:12 beed:13 bf08:12 bf09:13 bf24:12 bf25:13 bf40:12 bf41:13 bf5c:12 bf5d:13 " ++
  "bf78:12 bf79:13 bf94:12 bf95:13 bfb0:12 bfb1:13 bfcc:12 bfcd:13 bfe8:12 bfe9:13 c004:12 c005:13 " ++
  "c020:12 c021:13 c03c:12 c03d:13 c058:12 c059:13 c074:12 c075:13 c090:12 c091:13 c0ac:12 c0ad:13 " ++
  "c0c8:12 c0c9:13 c0e4:12 c0e5:13 c100:12 c101:13 c11c:12 c11d:13 c138:12 c139:13 c154:12 c155:13 " ++
  "c170:12 c171:13 c18c:12 c18d:13 c1a8:12 c1a9:13 c1c4:12 c1c5:13 c1e0:12 c1e1:13 c1fc:12 c1fd:13 " ++
  "c218:12 c219:13 c234:12 c235:13 c250:12 c251:13 c26c:12 c26d:13 c288:12 c289:13 c2a4:12 c2a5:13 " ++
  "c2c0:12 c2c1:13 c2dc:12 c2dd:13 c2f8:12 c2f9:13 c314:12 c315:13 c330:12 c331:13 c34c:12 c34d:13 " ++
  "c368:12 c369:13 c384:12 c385:13 c3a0:12 c3a1:13 c3bc:12 c3bd:13 c3d8:12 c3d9:13 c3f4:12 c3f5:13 " ++
  "c410:12 c411:13 c42c:12 c42d:13 c448:12 c449:13 c464:12 c465:13 c480:12 c481:13 c49c:12 c49d:13 " ++
  "c4b8:12 c4b9:13 c4d4:12 c4d5:13 c4f0:12 c4f1:13 c50c:12 c50d:13 c528:12 c529:13 c544:12 c545:13 " ++
  "c560:12 c561:13 c57c:12 c57d:13 c598:12 c599:13 c5b4:12 c5b5:13 c5d0:12 c5d1:13 c5ec:12 c5ed:13 " ++
  "c608:12 c609:13 c624:12 c625:13 c640:12 c641:13 c65c:12 c65d:13 c678:12 c679:13 c694:12 c695:13 " ++
  "c6b0:12 c6b1:13 c6cc:12 c6cd:13 c6e8:12 c6e9:13 c704:12 c705:13 c720:12 c721:13 c73c:12 c73d:13 " ++
  "c758:12 c759:13 c774:12 c775:13 c790:12 c791:13 c7ac:12 c7ad:13 c7c8:12 c7c9:13 c7e4:12 c7e5:13 " ++
  "c800:12 c801:13 c81c:12 c81d:13 c838:12 c839:13 c854:12 c855:13 c870:12 c871:13 c88c:12 c88d:13 " ++
  "c8a8:12 c8a9:13 c8c4:12 c8c5:13 c8e0:12 c8e1:13 c8fc:12 c8fd:13 c918:12 c919:13 c934:12 c935:13 " ++
  "c950:12 c951:13 c96c:12 c96d:13 c988:12 c989:13 c9a4:12 c9a5:13 c9c0:12 c9c1:13 c9dc:12 c9dd:13 " ++
  "c9f8:12 c9f9:13 ca14:12 ca15:13 ca30:12 ca31:13 ca4c:12 ca4d:13 ca68:12 ca69:13 ca84:12 ca85:13 " ++
  "caa0:12 caa1:13 cabc:12 cabd:13 cad8:12 cad9:13 caf4:12 caf5:13 cb10:12 cb11:13 cb2c:12 cb2d:13 " ++
  "cb48:12 cb49:13 cb64:12 cb65:13 cb80:12 cb81:13 cb9c:12 cb9d:13 cbb8:12 cbb9:13 cbd4:12 cbd5:13 " ++
  "cbf0:12 cbf1:13 cc0c:12 cc0d:13 cc28:12 cc29:13 cc44:12 cc45:13 cc60:12 cc61:13 cc7c:12 cc7d:13 " ++
  "cc98:12 cc99:13 ccb4:12 ccb5:13 ccd0:12 ccd1:13 ccec:12 cced:13 cd08:12 cd09:13 cd24:12 cd25:13 " ++
  "cd40:12 cd41:13 cd5c:12 cd5d:13 cd78:12 cd79:13 cd94:12 cd95:13 cdb0:12 cdb1:13 cdcc:12 cdcd:13 " ++
  "cde8:12 cde9:13 ce04:12 ce05:13 ce20:12 ce21:13 ce3c:12 ce3d:13 ce58:12 ce59:13 ce74:12 ce75:13 " ++
  "ce90:12 ce91:13 ceac:12 cead:13 cec8:12 cec9:13 cee4:12 cee5:13 cf00:12 cf01:13 cf1c:12 cf1d:13 " ++
  "cf38:12 cf39:13 cf54:12 cf55:13 cf70:12 cf71:13 cf8c:12 cf8d:13 cfa8:12 cfa9:13 cfc4:12 cfc5:13 " ++
  "cfe0:12 cfe1:13 cffc:12 cffd:13 d018:12 d019:13 d034:12 d035:13 d050:12 d051:13 d06c:12 d06d:13 " ++
  "d088:12 d089:13 d0a4:12 d0a5:13 d0c0:12 d0c1:13 d0dc:12 d0dd:13 d0f8:12 d0f9:13 d114:12 d115:13 " ++
  "d130:12 d131:13 d14c:12 d14d:13 d168:12 d169:13 d184:12 d185:13 d1a0:12 d1a1:13 d1bc:12 d1bd:13 " ++
  "d1d8:12 d1d9:13 d1f4:12 d1f5:13 d210:12 d211:13 d22c:12 d22d:13 d248:12 d249:13 d264:12 d265:13 " ++
  "d280:12 d281:13 d29c:12 d29d:13 d2b8:12 d2b9:13 d2d4:12 d2d5:13 d2f0:12 d2f1:13 d30c:12 d30d:13 " ++
  "d328:12 d329:13 d344:12 d345:13 d360:12 d361:13 d37c:12 d37d:13 d398:12 d399:13 d3b4:12 d3b5:13 " ++
  "d3d0:12 d3d1:13 d3ec:12 d3ed:13 d408:12 d409:13 d424:12 d425:13 d440:12 d441:13 d45c:12 d45d:13 " ++
  "d478:12 d479:13 d494:12 d495:13 d4b0:12 d4b1:13 d4cc:12 d4cd:13 d4e8:12 d4e9:13 d504:12 d505:13 " ++
  "d520:12 d521:13 d53c:12 d53d:13 d558:12 d559:13 d574:12 d575:13 d590:12 d591:13 d5ac:12 d5ad:13 " ++
  "d5c8:12 d5c9:13 d5e4:12 d5e5:13 d600:12 d601:13 d61c:12 d61d:13 d638:12 d639:13 d654:12 d655:13 " ++
  "d670:12 d671:13 d68c:12 d68d:13 d6a8:12 d6a9:13 d6c4:12 d6c5:13 d6e0:12 d6e1:13 d6fc:12 d6fd:13 " ++
  "d718:12 d719:13 d734:12 d735:13 d750:12 d751:13 d76c:12 d76d:13 d788:12 d789:13 d7a4:0 d7b0:10 " ++
  "d7c7:0 d7cb:11 d7fc:0 d800:3 e000:0 fb1e:4 fb1f:0 fe00:4 fe10:0 fe20:4 fe30:0 feff:3 ff00:0 " ++
  "ff9e:4 ffa0:0 fff0:3 fffc:0 101fd:4 101fe:0 102e0:4 102e1:0 10376:4 1037b:0 10a00:32 10a01:4 " ++
  "10a04:0 10a05:4 10a07:0 10a0c:4 10a10:32 10a14:0 10a15:32 10a18:0 10a19:32 10a36:0 10a38:4 " ++
  "10a3b:0 10a3f:4 10a40:0 10ae5:4 10ae7:0 10d24:4 10d28:0 10d69:4 10d6e:0 10eab:4 10ead:0 10efa:4 " ++
  "10f00:0 10f46:4 10f51:0 10f82:4 10f86:0 11000:8 11001:4 11002:8 11003:0 11038:4 11047:0 11070:4 " ++
  "11071:0 11073:4 11075:0 1107f:4 11082:8 11083:0 110b0:8 110b3:4 110b7:8 110b9:4 110bb:0 110bd:7 " ++
  "110be:0 110c2:4 110c3:0 110cd:7 110ce:0 11100:4 11103:32 11127:4 1112c:8 1112d:4 11135:0 " ++
  "11144:32 11145:8 11147:32 11148:0 11173:4 11174:0 11180:4 11182:8 11183:0 111b3:8 111b6:4 " ++
  "111bf:8 111c0:4 111c1:0 111c2:7 111c4:0 111c9:4 111cd:0 111ce:8 111cf:4 111d0:0 1122c:8 1122f:4 " ++
  "11232:8 11234:4 11238:0 1123e:4 1123f:0 11241:4 11242:0 112df:4 112e0:8 112e3:4 112eb:0 11300:4 " ++
  "11302:8 11304:0 1133b:4 1133d:0 1133e:4 1133f:8 11340:4 11341:8 11345:0 11347:8 11349:0 1134b:8 " ++
  "1134d:4 1134e:0 11357:4 11358:0 11362:8 11364:0 11366:4 1136d:0 11370:4 11375:0 11380:32 " ++
  "1138a:0 1138b:32 1138c:0 1138e:32 1138f:0 11390:32 113b6:0 113b8:4 113b9:8 113bb:4 113c1:0 " ++
  "113c2:4 113c3:0 113c5:4 113c6:0 113c7:4 113ca:8 113cb:0 113cc:8 113ce:4 113d1:7 113d2:4 113d3:0 " ++
  "113e1:4 113e3:0 11435:8 11438:4 11440:8 11442:4 11445:8 11446:4 11447:0 1145e:4 1145f:0 114b0:4 " ++
  "114b1:8 114b3:4 114b9:8 114ba:4 114bb:8 114bd:4 114be:8 114bf:4 114c1:8 114c2:4 114c4:0 115af:4 " ++
  "115b0:8 115b2:4 115b6:0 115b8:8 115bc:4 115be:8 115bf:4 115c1:0 115dc:4 115de:0 11630:8 11633:4 " ++
  "1163b:8 1163d:4 1163e:8 1163f:4 11641:0 116ab:4 116ac:8 116ad:4 116ae:8 116b0:4 116b8:0 1171d:4 " ++
  "1171e:8 1171f:4 11720:0 11722:4 11726:8 11727:4 1172c:0 1182c:8 1182f:4 11838:8 11839:4 1183b:0 " ++
  "11900:32 11907:0 11909:32 1190a:0 1190c:32 11914:0 11915:32 11917:0 11918:32 11930:4 11931:8 " ++
  "11936:0 11937:8 11939:0 1193b:4 1193f:7 11940:8 11941:7 11942:8 11943:4 11944:0 119d1:8 119d4:4 " ++
  "119d8:0 119da:4 119dc:8 119e0:4 119e1:0 119e4:8 119e5:0 11a00:32 11a01:4 11a0b:32 11a33:4 " ++
  "11a39:8 11a3a:0 11a3b:4 11a3f:0 11a47:4 11a48:0 11a50:32 11a51:4 11a57:8 11a59:4 11a5c:32 " ++
  "11a84:7 11a8a:4 11a97:8 11a98:4 11a9a:0 11b60:4 11b61:8 11b62:4 11b65:8 11b66:4 11b67:8 11b68:0 " ++
  "11c2f:8 11c30:4 11c37:0 11c38:4 11c3e:8 11c3f:4 11c40:0 11c92:4 11ca8:0 11ca9:8 11caa:4 11cb1:8 " ++
  "11cb2:4 11cb4:8 11cb5:4 11cb7:0 11d31:4 11d37:0 11d3a:4 11d3b:0 11d3c:4 11d3e:0 11d3f:4 11d46:7 " ++
  "11d47:4 11d48:0 11d8a:8 11d8f:0 11d90:4 11d92:0 11d93:8 11d95:4 11d96:8 11d97:4 11d98:0 11ef3:4 " ++
  "11ef5:8 11ef7:0 11f00:4 11f02:7 11f03:8 11f04:32 11f11:0 11f12:32 11f34:8 11f36:4 11f3b:0 " ++
  "11f3e:8 11f40:4 11f43:0 11f5a:4 11f5b:0 13430:3 13440:4 13441:0 13447:4 13456:0 1611e:4 1612a:8 " ++
  "1612d:4 16130:0 16af0:4 16af5:0 16b30:4 16b37:0 16f4f:4 16f50:0 16f51:8 16f88:0 16f8f:4 16f93:0 " ++
  "16fe4:4 16fe5:0 16ff0:4 16ff2:0 1bc9d:4 1bc9f:0 1bca0:3 1bca4:0 1cf00:4 1cf2e:0 1cf30:4 1cf47:0 " ++
  "1d165:4 1d16a:0 1d16d:4 1d173:3 1d17b:4 1d183:0 1d185:4 1d18c:0 1d1aa:4 1d1ae:0 1d242:4 1d245:0 " ++
  "1da00:4 1da37:0 1da3b:4 1da6d:0 1da75:4 1da76:0 1da84:4 1da85:0 1da9b:4 1daa0:0 1daa1:4 1dab0:0 " ++
  "1e000:4 1e007:0 1e008:4 1e019:0 1e01b:4 1e022:0 1e023:4 1e025:0 1e026:4 1e02b:0 1e08f:4 1e090:0 " ++
  "1e130:4 1e137:0 1e2ae:4 1e2af:0 1e2ec:4 1e2f0:0 1e4ec:4 1e4f0:0 1e5ee:4 1e5f0:0 1e6e3:4 1e6e4:0 " ++
  "1e6e6:4 1e6e7:0 1e6ee:4 1e6f0:0 1e6f5:4 1e6f6:0 1e8d0:4 1e8d7:0 1e944:4 1e94b:0 1f004:16 " ++
  "1f005:0 1f02c:16 1f030:0 1f094:16 1f0a0:0 1f0af:16 1f0b1:0 1f0c0:16 1f0c1:0 1f0cf:16 1f0d1:0 " ++
  "1f0f6:16 1f100:0 1f170:16 1f172:0 1f17e:16 1f180:0 1f18e:16 1f18f:0 1f191:16 1f19b:0 1f1ae:16 " ++
  "1f1e6:6 1f200:0 1f201:16 1f210:0 1f21a:16 1f21b:0 1f22f:16 1f230:0 1f232:16 1f23b:0 1f23c:16 " ++
  "1f240:0 1f249:16 1f260:0 1f266:16 1f322:0 1f324:16 1f394:0 1f396:16 1f398:0 1f399:16 1f39c:0 " ++
  "1f39e:16 1f3f1:0 1f3f3:16 1f3f6:0 1f3f7:16 1f3fb:4 1f400:16 1f4fe:0 1f4ff:16 1f53e:0 1f549:16 " ++
  "1f54f:0 1f550:16 1f568:0 1f56f:16 1f571:0 1f573:16 1f57b:0 1f587:16 1f588:0 1f58a:16 1f58e:0 " ++
  "1f590:16 1f591:0 1f595:16 1f597:0 1f5a4:16 1f5a6:0 1f5a8:16 1f5a9:0 1f5b1:16 1f5b3:0 1f5bc:16 " ++
  "1f5bd:0 1f5c2:16 1f5c5:0 1f5d1:16 1f5d4:0 1f5dc:16 1f5df:0 1f5e1:16 1f5e2:0 1f5e3:16 1f5e4:0 " ++
  "1f5e8:16 1f5e9:0 1f5ef:16 1f5f0:0 1f5f3:16 1f5f4:0 1f5fa:16 1f650:0 1f680:16 1f6c6:0 1f6cb:16 " ++
  "1f6d3:0 1f6d5:16 1f6e6:0 1f6e9:16 1f6ea:0 1f6eb:16 1f6f1:0 1f6f3:16 1f700:0 1f7da:16 1f800:0 " ++
  "1f80c:16 1f810:0 1f848:16 1f850:0 1f85a:16 1f860:0 1f888:16 1f890:0 1f8ae:16 1f8b0:0 1f8bc:16 " ++
  "1f8c0:0 1f8c2:16 1f8d0:0 1f8d9:16 1f900:0 1f90c:16 1f93b:0 1f93c:16 1f946:0 1f947:16 1fa00:0 " ++
  "1fa58:16 1fa60:0 1fa6e:16 1fb00:0 1fc00:16 1fffe:0 e0000:3 e0020:4 e0080:3 e0100:4 e01f0:3 " ++
  "e1000:0 "

def hexVal (cs : List Char) : Nat :=
  cs.foldl (fun n c => n * 16 + (if c.isDigit then c.toNat - '0'.toNat else c.toNat - 'a'.toNat + 10)) 0

def table : Array (Nat × Nat) :=
  ((tableText.splitOn " ").filterMap fun e => match e.splitOn ":" with
    | [a, b] => b.toNat?.map fun k => (hexVal a.toList, k)
    | _ => none).toArray

/-- The class of `c`: the last entry at or below it (binary search). -/
def classOf (c : Char) : Nat := Id.run do
  let v := c.toNat
  let mut lo := 0
  let mut hi := table.size
  -- table[lo].1 ≤ v < table[hi].1
  while lo + 1 < hi do
    let mid := (lo + hi) / 2
    if table[mid]!.1 ≤ v then lo := mid else hi := mid
  return table[lo]!.2

def gcb (k : Nat) : Nat := k % 16
def pict (k : Nat) : Bool := k / 16 % 2 == 1
/-- `_isInCBConsonant`. -/
def consonant (k : Nat) : Bool := k / 32 == 1
/-- `_isInCBLinker`: Swift's six viramas (Devanagari, Bengali, Gujarati, Oriya, Telugu,
Malayalam), not Unicode 17's list. -/
def linker (k : Nat) : Bool := k / 32 == 3
def isControl (k : Nat) : Bool := gcb k == 1 || gcb k == 2 || gcb k == 3
def isExtendOrZwj (k : Nat) : Bool := gcb k == 4 || gcb k == 5

/-- `_isInCBExtend`, for an Extend or ZWJ scalar. -/
def incbExtend (c : Char) (k : Nat) : Bool := !(consonant k || linker k || c.val == 0x200C)

/-- Swift's `_GraphemeBreakingState`, fresh at each character's start. -/
structure State where
  linker : Bool := false
  emoji : Bool := false
  indic : Bool := false
  breakRI : Bool := false

/-- `_GraphemeBreakingState.shouldBreak(between:and:)`: a boundary between `c1` and `c2`
(classes `k1`, `k2`), and the state after. -/
def shouldBreak (st : State) (c1 : Char) (k1 : Nat) (c2 : Char) (k2 : Nat) : Bool × State :=
  let x := gcb k1
  let y := gcb k2
  if x == 1 && y == 2 then (false, st)                                     -- GB3
  else if isControl k1 then (true, st)                                     -- GB4
  else
    let st0 := { st with emoji := false, indic := false }
    if isControl k2 then (true, st0)                                       -- GB5
    else if x == 9 && (y == 9 || y == 10 || y == 12 || y == 13) then (false, st0)  -- GB6
    else if (x == 12 || x == 10) && (y == 10 || y == 11) then (false, st0)          -- GB7
    else if (x == 13 || x == 11) && y == 11 then (false, st0)                       -- GB8
    else if isExtendOrZwj k2 then                                          -- GB9
      let emoji := pict k1 || (st.emoji && x == 4)
      let e2 := incbExtend c2 k2
      let l2 := linker k2
      let st1 := { st0 with emoji }
      if consonant k1 && e2 && !l2 then (false, { st1 with indic := true })
      else if consonant k1 && !e2 && l2 then (false, { st1 with indic := true, linker := true })
      else if !consonant k1 && e2 && !l2 && st.indic then (false, { st1 with indic := true })
      else if !consonant k1 && !e2 && l2 && st.indic then
        (false, { st1 with indic := true, linker := true })
      else (false, st1)
    else if y == 8 then (false, st0)                                       -- GB9a
    else if x == 7 then (false, st0)                                       -- GB9b
    else if x == 5 && pict k2 then (!st.emoji, st0)                        -- GB11
    else if x == 6 && y == 6 then (st.breakRI, { st0 with breakRI := !st.breakRI })  -- GB12, GB13
    else if st.indic && st.linker && consonant k2 then (false, { st0 with linker := false })  -- GB9c
    else (true, st0)                                                       -- GB999

/-- The text's characters (grapheme clusters), in order, as Swift's
`_nextGraphemeClusterBoundary` finds them: each from a fresh state. -/
def clusters (cs : List Char) : List (List Char) :=
  let rec go (st : State) (c : Char) (k : Nat) (cur : List Char) (acc : List (List Char)) :
      List Char → List (List Char)
    | [] => ((c :: cur).reverse :: acc).reverse
    | d :: ds =>
      let kd := classOf d
      let (b, st') := shouldBreak st c k d kd
      if b then go {} d kd [] ((c :: cur).reverse :: acc) ds
      else go st' d kd (c :: cur) acc ds
  match cs with
  | [] => []
  | c :: rest => go {} c (classOf c) [] [] rest

/-- Swift's `_shouldBreakWithLookback`, walking backwards: a boundary between the last
character of `before` and `c2`. `before` is the text before `c2`, reversed (nearest first). -/
def breaksBack (before : List Char) (c2 : Char) : Bool :=
  match before with
  | [] => true
  | c1 :: earlier =>
    let k1 := classOf c1
    let k2 := classOf c2
    let x := gcb k1
    let y := gcb k2
    if x == 1 && y == 2 then false                                         -- GB3
    else if isControl k1 || isControl k2 then true                         -- GB4, GB5
    else if x == 9 && (y == 9 || y == 10 || y == 12 || y == 13) then false -- GB6
    else if (x == 12 || x == 10) && (y == 10 || y == 11) then false        -- GB7
    else if (x == 13 || x == 11) && y == 11 then false                     -- GB8
    else if isExtendOrZwj k2 then false                                    -- GB9
    else if y == 8 then false                                              -- GB9a
    else if x == 7 then false                                              -- GB9b
    else if x == 5 && pict k2 then                                         -- GB11
      -- `_checkIfInEmojiSequence`: past any Extend, a pictograph.
      match earlier.dropWhile (fun p => gcb (classOf p) == 4) with
      | p :: _ => !pict (classOf p)
      | [] => true
    else if x == 6 && y == 6 then                                          -- GB12, GB13
      -- `_countRIs`: an odd run of regional indicators before `c1` breaks.
      (earlier.takeWhile (fun p => gcb (classOf p) == 6)).length % 2 == 1
    else if consonant k2 && isExtendOrZwj k1 && (incbExtend c1 k1 || linker k1) then  -- GB9c
      -- `_checkIfInIndicSequence`.
      let rec walk (seen : Bool) : List Char → Bool
        | [] => false
        | p :: ps =>
          let kp := classOf p
          if consonant kp then seen
          else if !isExtendOrZwj kp then false
          else
            let e := incbExtend p kp
            let l := linker kp
            if !e && !l then false
            else if !e && l then walk true ps
            else if e && !l then walk seen ps
            else false
      !walk (linker k1) earlier
    else true                                                              -- GB999

/-- The last `n` characters, found walking backwards as Swift's `index(before:)` does. -/
def takeEndChars (n : Nat) (cs : List Char) : List Char :=
  -- `rev` is the text still before the cut, reversed; `out` the characters taken.
  let rec go (fuel : Nat) (n : Nat) (rev : List Char) (out : List Char) : List Char :=
    match fuel, n, rev with
    | 0, _, _ => out
    | _, 0, _ => out
    | _, _, [] => out
    | fuel + 1, n + 1, c :: before =>
      -- One character: take scalars back to a boundary.
      let rec back (fuel : Nat) (c : Char) (before : List Char) (acc : List Char) :
          List Char × List Char :=
        match fuel with
        | 0 => (before, c :: acc)
        | fuel + 1 =>
          if breaksBack before c then (before, c :: acc)
          else match before with
            | [] => (before, c :: acc)
            | b :: bs => back fuel b bs (c :: acc)
      let (before', ch) := back (before.length + 1) c before []
      go fuel n before' (ch ++ out)
  go (cs.length + 1) n cs.reverse []

/-- `String.count`. -/
def count (s : String) : Nat := (clusters s.toList).length

/-- `String.prefix(n)`. -/
def take (n : Nat) (s : String) : String := String.join ((clusters s.toList).take n |>.map String.ofList)

/-- `String.suffix(n)`. -/
def takeEnd (n : Nat) (s : String) : String := String.ofList (takeEndChars n s.toList)

/-- `String.hasPrefix(p)`: `p`'s characters begin the text's. Swift compares characters up to
canonical equivalence; this compares them exactly, which is the same for a `p` whose
characters have no other canonical form (`"#"`). -/
def hasPrefix (s p : String) : Bool :=
  let a := clusters s.toList
  let b := clusters p.toList
  a.take b.length == b

end Examples.Yap.Graphemes
