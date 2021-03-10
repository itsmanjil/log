from tkinter import *
from tkinter import messagebox
from tkinter import ttk
import frontend.register
import backend.dbconnection
import mysql.connector as ms
import model.user


class Dashboard:
    def __init__(self, root):
        self.root = root
        self.root.title('Update')
        self.root.geometry('900x530')
        root.configure(bg='#074463')

        self.db = backend.dbconnection.DBConnect()
        self.username = StringVar()
        self.password = StringVar()
        self.sort = StringVar()

        self.gender = StringVar()
        self.address = StringVar()
        self.collegeID = StringVar()

        lb = Label(self.root, text='Update', font=('arial', 20, 'bold'))
        lb.pack(fill=X)

        main_frame = Frame(self.root, bd=10, bg='#074463')
        main_frame.place(x=0, y=180, width=400, height=450)

        Table_Frame = Frame(self.root, bd=4, relief=RIDGE, bg="powderblue")
        Table_Frame.place(x=400, y=180, width=500, height=350)

        scroll_x = Scrollbar(Table_Frame, orient=HORIZONTAL)
        scroll_y = Scrollbar(Table_Frame, orient=VERTICAL)
        self.student_table = ttk.Treeview(Table_Frame,
                                          columns=("collegeID", "Username", "gender", "Address"),
                                          xscrollcommand=scroll_x.set, yscrollcommand=scroll_y.set)
        scroll_x.pack(side=BOTTOM, fill=X)
        scroll_y.pack(side=RIGHT, fill=Y)
        scroll_x.config(command=self.student_table.xview)
        scroll_y.config(command=self.student_table.yview)

        self.student_table.heading("collegeID", text="CollegeID")
        self.student_table.heading("Username", text="Username")
        self.student_table.heading("gender", text="Gender")
        self.student_table.heading("Address", text="Address")
        self.student_table['show'] = 'headings'
        self.student_table.pack()

        self.student_table.column("collegeID", width=100)
        self.student_table.column("Username", width=100)
        self.student_table.column("gender", width=100)
        self.student_table.column("Address", width=100)
        self.student_table.pack(fill=BOTH, expand=1)
        self.fetch_data()
        self.student_table.bind("<ButtonRelease-1>", self.get_cursor)

        lbl_college = Label(main_frame, text='college ID', font=('arial', 15, 'bold'), bg='#074463')
        lbl_college.grid(row=1, column=0, padx=8, pady=10)

        self.ent_college = Entry(main_frame, textvariable=self.collegeID, font=('arial', 15, 'bold'))
        self.ent_college.grid(row=1, column=1, padx=8, pady=10)

        lbl_uname = Label(main_frame, text='User Name', font=('arial', 15, 'bold'), bg='#074463')
        lbl_uname.grid(row=2, column=0, padx=8, pady=10)

        self.ent_uname = Entry(main_frame, textvariable=self.username, font=('arial', 15, 'bold'))
        self.ent_uname.grid(row=2, column=1, padx=8, pady=10)

        lbl_password = Label(main_frame, text='Password', font=('arial', 15, 'bold'), \
                             bg='#074463')
        lbl_password.grid(row=3, column=0, padx=8, pady=10)

        self.ent_password = Entry(main_frame, textvariable=self.password, font=('arial', 15, 'bold'))
        self.ent_password.grid(row=3, column=1, padx=8, pady=10)

        lbl_add = Label(main_frame, text='Address', font=('arial', 15, 'bold'), \
                        bg='#074463')
        lbl_add.grid(row=4, column=0, padx=8, pady=10)

        self.ent_add = Entry(main_frame, textvariable=self.address, font=('arial', 15, 'bold'))
        self.ent_add.grid(row=4, column=1, padx=8, pady=10)

        lbl_cmb = Label(main_frame, text='Gender', font=('arial', 15, 'bold'), \
                        background='#074463')
        lbl_cmb.grid(row=5, column=0)

        self.cmb_gender = ttk.Combobox(main_frame, textvariable=self.gender, font=('arial', 15, 'bold'),
                                       state="readonly")
        self.cmb_gender['values'] = ('Male', 'Female', 'Others')
        self.cmb_gender.grid(row=5, column=1)

        btn_search = Button(self.root, text='Search', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE,
                            command=self.search_data,
                            padx=5)
        btn_search.place(x=140, y=145)

        btn_update = Button(main_frame, text='Update', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE,
                            command=self.update,
                            padx=5)
        btn_update.place(x=0, y=250)

        btn_reset = Button(self.root, text='Reset', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE,
                           command=self.reset_click, padx=5)
        btn_reset.place(x=130, y=440)

        btn_del = Button(self.root, text='Delete', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE,
                         padx=5)
        btn_del.place(x=250, y=440)

        sort_by = Label(self.root, text=" Sort By :", fg="black", font=("times new roman", 19, "bold"))
        sort_by.place(x=450, y=140)

        self.bsort = Button(self.root, text=" Sort ", fg="black", font=("times new roman", 15, "bold"),
                            command=self.sorted
                            )
        self.bsort.place(x=745, y=139)

        self.combo_sort = ttk.Combobox(self.root, textvariable=self.sort, font=("times new roman", 19, "bold"),
                                       state='readonly', width=12)
        self.combo_sort['values'] = ("CollegeID", "UserName")
        self.combo_sort.place(x=560, y=140)

    def reset_click(self):
        self.ent_college.delete(0, END)
        self.ent_college.insert(0, "")
        self.ent_uname.delete(0, END)
        self.ent_uname.insert(0, "")
        self.ent_password.insert(0, '')
        self.ent_password.delete(0, END)
        self.ent_add.delete(0, END)
        self.ent_add.insert(0, '')
        self.fetch_data()

    def get_cursor(self, event):
        curosor_row = self.student_table.focus()
        contents = self.student_table.item(curosor_row)
        row = contents['values']
        self.collegeID.set(row[0])
        self.username.set(row[1])
        self.gender.set(row[2])
        self.address.set(row[3])

    def fetch_data(self):
        self.con = ms.connect(host='localhost', user='root', password='@um1gbi3', database='login1')
        self.cur = self.con.cursor()

        self.cur.execute("select college,username,gender,address from new_table ")

        rows = self.cur.fetchall()
        if len(rows) != 0:
            self.student_table.delete(*self.student_table.get_children())
            for row in rows:
                self.student_table.insert('', END, values=row)
            self.con.commit()
        self.con.close()

    def update(self):
        username = self.ent_uname.get()
        password = self.ent_password.get()
        add = self.ent_add.get()
        gender = self.cmb_gender.get()
        college = self.ent_college.get()

        if username == '' or password == '' or add == '' or gender == '' or college == '':
            messagebox.showerror('Error', 'plz fill the empty field')

        else:
            u = model.user.User(username, password, add, gender, college)
            query = "update new_table set username=%s,password=%s, Address=%s, gender=%s, college=%s"
            values = (u.get_username(), u.get_password(), u.get_address(), u.get_gender(), u.get_college())
            self.db.update(query, values)
            self.fetch_data()
            self.reset_click()

            messagebox.showinfo("Update status", "Update Succesfuly")

    def sorted(self):
        query = "select college,username,gender,address from new_table"

        rows = self.db.select(query)
        myStack = []
        if len(rows) != 0:
            self.student_table.delete(*self.student_table.get_children())
            if self.sort.get() == "CollegeID":
                for row in rows:
                    myStack.append(row[0])
                self.sorted = self.mergesort(myStack)

                for i in self.sorted:
                    for row in rows:
                        if i == row[0]:
                            self.student_table.insert('', END, value=row)
                            rows.remove(row)
            else:
                self.student_table.delete(*self.student_table.get_children())
                if self.sort.get() == "UserName":
                    for row in rows:
                        myStack.append(row[1])
                    self.sorted = self.mergesort(myStack)

                    for i in self.sorted:
                        for row in rows:
                            if i == row[1]:
                                self.student_table.insert('', END, value=row)
                                rows.remove(row)

    @classmethod
    def mergesort(self, alist):
        if len(alist) > 1:
            mid = len(alist) // 2
            lefthalf = alist[:mid]
            righthalf = alist[mid:]
            self.mergesort(lefthalf)
            self.mergesort(righthalf)
            i = 0
            j = 0
            k = 0
            while i < len(lefthalf) and j < len(righthalf):
                if lefthalf[i] < righthalf[j]:
                    alist[k] = lefthalf[i]
                    i = i + 1
                else:
                    alist[k] = righthalf[j]
                    j += 1
                k += 1
            while i < len(lefthalf):
                alist[k] = lefthalf[i]
                i += 1
                k += 1
            while j < len(righthalf):
                alist[k] = righthalf[j]
                j += 1
                k += 1
        return alist

    @classmethod
    def binary_Collgeid(self, list, item):
        if list == []:
            return ValueError
        self.list = list
        self.item = item
        max = len(list) - 1
        min = 0
        while min <= max:
            mid = (min + max) // 2
            if self.list[mid] == self.item:
                return mid
            elif self.list[mid] > self.item:
                max = mid - 1
            else:
                min = mid + 1
        return -1

    def search_data(self):
        query = "select college,username,gender,address from new_table"
        rows = self.db.select(query)
        myStack = []
        for row in rows:
            myStack.append(row[0])
        self.sorted = self.mergesort(myStack)
        print(self.sorted)
        item = int(self.collegeID.get())
        print(item)
        sorted = self.sorted
        index = self.binary_Collgeid(sorted, item)
        print(index)
        for row in rows:
            if sorted[index] == row[0]:
                self.student_table.delete(*self.student_table.get_children())
                self.student_table.insert('', END, value=row)
                self.collegeID.set("")


root = Tk()
Dashboard(root)
root.mainloop()
