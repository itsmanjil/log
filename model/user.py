class User:
    def __init__(self, uname, passw, add, gen, college):
        self.__username = uname
        self.__password = passw
        self.__address = add
        self.__gen = gen
        self.__college = college

    def set_username(self, uname):
        self.__username = uname

    def get_username(self):
        return self.__username

    def set_password(self, passw):
        self.__password = passw

    def get_password(self):
        return self.__password

    def set_address(self, addr):
        self.__address = addr

    def get_address(self):
        return self.__address

    def set_gender(self, gen):
        self.__gen = gen

    def get_gender(self):
        return self.__gen

    def set_college(self,college):
        self.__college = college

    def get_college(self):
        return self.__college
