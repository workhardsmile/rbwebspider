class String
  def to_big5
    iconv_chinese_by("to_big5.tab")
  end

  def to_gb2312
    iconv_chinese_by("to_gb2312.tab")
  end

  private
  def iconv_chinese_by(lang_table)
    lang_table=File.join(File.dirname(__FILE__),"lang_table",lang_table)
    fp=File.open(lang_table,"rb")
    s=self
    len=s.length-1
    i=0
    while(i<len)
      c=s[i]
      if c>=160
        n=s[i+1]
        if c==161 and n==64
          b=""
        else
        pos=(c - 160)*510 + (n - 1)*2
        fp.seek(pos)
        b=fp.read(2)
        end
      s[i]=b[0]
      s[i+1]=b[1]
      i+=1
      end
      i+=1
    end
    fp.close
    return s
  end
end

String a="愛人"
a.to_gb2312
