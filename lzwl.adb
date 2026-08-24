with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Indefinite_Vectors;

package body LZWL is

   -- A phrase is a sequence of syllables. Used as the Dictionary Key.
   type Phrase is array (Positive range <>) of Unbounded_String;
   
   -- Equality operator for Phrase arrays
   function "=" (L, R : Phrase) return Boolean is
   begin
      if L'Length /= R'Length then return False; end if;
      for I in 0 .. L'Length - 1 loop
         if L(L'First + I) /= R(R'First + I) then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   -- Less-than operator to allow usage in Ordered_Maps
   function "<" (L, R : Phrase) return Boolean is
   begin
      for I in 0 .. Natural'Min(L'Length, R'Length) - 1 loop
         if L(L'First + I) < R(R'First + I) then
            return True;
         elsif L(L'First + I) > R(R'First + I) then
            return False;
         end if;
      end loop;
      return L'Length < R'Length;
   end "<";
   
   -- Concatenation for Phrase arrays
   function "&" (L, R : Phrase) return Phrase is
      Result : Phrase (1 .. L'Length + R'Length);
   begin
      if L'Length > 0 then
         Result(1 .. L'Length) := L;
      end if;
      if R'Length > 0 then
         Result(L'Length + 1 .. Result'Last) := R;
      end if;
      return Result;
   end "&";

   package Phrase_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => Phrase,
      Element_Type => Code);
      
   package Code_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Natural,
      Element_Type => Phrase);
      
   -- =========================================================================
   -- Shared Helper: Initializes the dictionaries with alphabet baseline
   -- =========================================================================
   procedure Init_Dict (
      Alphabet  : in Syllable_Array;
      Dict_P2C  : out Phrase_Maps.Map;
      Dict_C2P  : out Code_Vectors.Vector;
      Next_Code : out Code) 
   is
      Empty_P : Phrase(1..1) := (1 => Null_Unbounded_String);
   begin
      Dict_P2C.Clear;
      Dict_C2P.Clear;
      
      -- Code_Vectors index aligns dynamically with appended order
      Dict_C2P.Append(Empty_P); -- Dummy insert for Index 0
      
      Next_Code := 1;
      
      -- Per LZWL spec: Initialize with Empty Syllable
      Dict_P2C.Insert(Empty_P, Next_Code);
      Dict_C2P.Append(Empty_P);
      Next_Code := Next_Code + 1;
      
      -- Initialize explicit Alphabet
      for I in Alphabet'Range loop
         declare
            P : Phrase(1..1) := (1 => Alphabet(I));
         begin
            if not Dict_P2C.Contains(P) then
               Dict_P2C.Insert(P, Next_Code);
               Dict_C2P.Append(P);
               Next_Code := Next_Code + 1;
            end if;
         end;
      end loop;
   end Init_Dict;

   -- =========================================================================
   -- Basic Syllable-Based Adaptation Implementations
   -- =========================================================================
   procedure Encode_Basic (
      Alphabet   : in Syllable_Array;
      Input      : in Syllable_Array;
      Output     : out Code_Array;
      Output_Len : out Natural)
   is
      Dict_P2C   : Phrase_Maps.Map;
      Dict_C2P   : Code_Vectors.Vector;
      Next_Code  : Code;
      S          : Phrase(1..0);
      C          : Phrase(1..1);
      Out_Offset : Natural := 0;
   begin
      Output_Len := 0;
      if Input'Length = 0 then return; end if;
      
      Init_Dict(Alphabet, Dict_P2C, Dict_C2P, Next_Code);
      
      for I in Input'Range loop
         C(1) := Input(I);
         
         if not Dict_P2C.Contains(C) then
            raise LZWL_Error with "Syllable not in alphabet: " & To_String(Input(I));
         end if;
         
         declare
            Combined : Phrase := S & C;
         begin
            if Dict_P2C.Contains(Combined) then
               S := Combined;
            else
               if Out_Offset >= Output'Length then
                  raise LZWL_Error with "Output buffer overflow";
               end if;
               Output(Output'First + Out_Offset) := Dict_P2C.Element(S);
               Out_Offset := Out_Offset + 1;
               
               Dict_P2C.Insert(Combined, Next_Code);
               Dict_C2P.Append(Combined);
               Next_Code := Next_Code + 1;
               
               S := C;
            end if;
         end;
      end loop;
      
      if S'Length > 0 then
         if Out_Offset >= Output'Length then
            raise LZWL_Error with "Output buffer overflow";
         end if;
         Output(Output'First + Out_Offset) := Dict_P2C.Element(S);
         Out_Offset := Out_Offset + 1;
      end if;
      
      Output_Len := Out_Offset;
   end Encode_Basic;

   procedure Decode_Basic (
      Alphabet   : in Syllable_Array;
      Input      : in Code_Array;
      Output     : out Syllable_Array;
      Output_Len : out Natural)
   is
      Dict_P2C   : Phrase_Maps.Map;
      Dict_C2P   : Code_Vectors.Vector;
      Next_Code  : Code;
      Prev_S     : Phrase(1..0);
      S1         : Phrase(1..0);
      Out_Offset : Natural := 0;
   begin
      Output_Len := 0;
      if Input'Length = 0 then return; end if;
      
      Init_Dict(Alphabet, Dict_P2C, Dict_C2P, Next_Code);
      
      for I in Input'Range loop
         declare
            K : Code := Input(I);
         begin
            if Natural(K) >= Natural(Next_Code) then
               if I = Input'First then
                  raise LZWL_Error with "Invalid data: Bad initial code";
               end if;
               declare
                  First_Syllable : Phrase(1..1) := (1 => Prev_S(Prev_S'First));
                  Missing_Phrase : Phrase := Prev_S & First_Syllable;
               begin
                  S1 := Missing_Phrase;
               end;
            else
               S1 := Dict_C2P.Element(Natural(K));
            end if;
            
            for J in S1'Range loop
               if S1(J) /= Null_Unbounded_String then
                  if Out_Offset >= Output'Length then
                     raise LZWL_Error with "Output array too small";
                  end if;
                  Output(Output'First + Out_Offset) := S1(J);
                  Out_Offset := Out_Offset + 1;
               end if;
            end loop;
            
            if Prev_S'Length > 0 then
               declare
                  First_Syllable : Phrase(1..1) := (1 => S1(S1'First));
                  New_Phrase     : Phrase := Prev_S & First_Syllable;
               begin
                  Dict_P2C.Insert(New_Phrase, Next_Code);
                  Dict_C2P.Append(New_Phrase);
                  Next_Code := Next_Code + 1;
               end;
            end if;
            
            Prev_S := S1;
         end;
      end loop;
      
      Output_Len := Out_Offset;
   end Decode_Basic;

   -- =========================================================================
   -- Dictionary Expansion Variant Implementations
   -- =========================================================================
   procedure Encode_Expanded (
      Alphabet   : in Syllable_Array;
      Input      : in Syllable_Array;
      Output     : out Code_Array;
      Output_Len : out Natural)
   is
      Dict_P2C   : Phrase_Maps.Map;
      Dict_C2P   : Code_Vectors.Vector;
      Next_Code  : Code;
      S          : Phrase(1..0);
      C          : Phrase(1..1);
      Out_Offset : Natural := 0;
   begin
      Output_Len := 0;
      if Input'Length = 0 then return; end if;
      
      Init_Dict(Alphabet, Dict_P2C, Dict_C2P, Next_Code);
      
      for I in Input'Range loop
         C(1) := Input(I);
         
         if not Dict_P2C.Contains(C) then
            raise LZWL_Error with "Syllable not in alphabet";
         end if;
         
         declare
            Combined : Phrase := S & C;
         begin
            if Dict_P2C.Contains(Combined) then
               S := Combined;
            else
               if Out_Offset >= Output'Length then
                  raise LZWL_Error with "Output buffer overflow";
               end if;
               Output(Output'First + Out_Offset) := Dict_P2C.Element(S);
               Out_Offset := Out_Offset + 1;
               
               -- Dictionary Expansion Logic: S1 concatenated with S's initial 
               -- syllable (where C represents the subsequent string S1).
               if S'Length > 0 then
                  declare
                     S_First    : Phrase(1..1) := (1 => S(S'First));
                     New_Phrase : Phrase := C & S_First;
                  begin
                     if not Dict_P2C.Contains(New_Phrase) then
                        Dict_P2C.Insert(New_Phrase, Next_Code);
                        Dict_C2P.Append(New_Phrase);
                        Next_Code := Next_Code + 1;
                     end if;
                  end;
               end if;
               
               S := C;
            end if;
         end;
      end loop;
      
      if S'Length > 0 then
         if Out_Offset >= Output'Length then
            raise LZWL_Error with "Output buffer overflow";
         end if;
         Output(Output'First + Out_Offset) := Dict_P2C.Element(S);
         Out_Offset := Out_Offset + 1;
      end if;
      
      Output_Len := Out_Offset;
   end Encode_Expanded;

   procedure Decode_Expanded (
      Alphabet   : in Syllable_Array;
      Input      : in Code_Array;
      Output     : out Syllable_Array;
      Output_Len : out Natural)
   is
      Dict_P2C   : Phrase_Maps.Map;
      Dict_C2P   : Code_Vectors.Vector;
      Next_Code  : Code;
      Prev_S     : Phrase(1..0);
      S1         : Phrase(1..0);
      Out_Offset : Natural := 0;
   begin
      Output_Len := 0;
      if Input'Length = 0 then return; end if;
      
      Init_Dict(Alphabet, Dict_P2C, Dict_C2P, Next_Code);
      
      for I in Input'Range loop
         declare
            K : Code := Input(I);
         begin
            if Natural(K) >= Natural(Next_Code) then
               if I = Input'First then
                  raise LZWL_Error with "Invalid code detected";
               end if;
               -- Expansion variant: new phrase is constructed from preceding
               declare
                  Prev_First     : Phrase(1..1) := (1 => Prev_S(Prev_S'First));
                  Missing_Phrase : Phrase := Prev_First & Prev_First;
               begin
                  S1 := Missing_Phrase;
               end;
            else
               S1 := Dict_C2P.Element(Natural(K));
            end if;
            
            for J in S1'Range loop
               if S1(J) /= Null_Unbounded_String then
                  if Out_Offset >= Output'Length then
                     raise LZWL_Error with "Output buffer overflow";
                  end if;
                  Output(Output'First + Out_Offset) := S1(J);
                  Out_Offset := Out_Offset + 1;
               end if;
            end loop;
            
            if Prev_S'Length > 0 then
               declare
                  S1_First   : Phrase(1..1) := (1 => S1(S1'First));
                  Prev_First : Phrase(1..1) := (1 => Prev_S(Prev_S'First));
                  New_Phrase : Phrase := S1_First & Prev_First;
               begin
                  if not Dict_P2C.Contains(New_Phrase) then
                     Dict_P2C.Insert(New_Phrase, Next_Code);
                     Dict_C2P.Append(New_Phrase);
                     Next_Code := Next_Code + 1;
                  end if;
               end;
            end if;
            
            Prev_S := S1;
         end;
      end loop;
      
      Output_Len := Out_Offset;
   end Decode_Expanded;

end LZWL;
